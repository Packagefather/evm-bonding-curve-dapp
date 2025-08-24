// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin-contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable2Step.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {CurveToken} from "./CurveToken.sol";
import "./IFactory.sol";

contract BondingCurve is ReentrancyGuard, Pausable, Ownable(msg.sender) {
    using SafeTransferLib for address;

    IFactory public factory;
    address public token;
    bool private initialized;

    address public referrer;
    address public creator;
    mapping(address => address) public referrerOf;

    uint256 public allocationA; // ~80% of supply
    uint256 public curveLimit; // FDV at A (for sanity checks)

    // Virtual reserves (18 decimals assumed)
    uint256 public vToken; // starts at iVToken
    uint256 public vEth; // starts at iVEth

    // State
    uint256 public sold; // total tokens sold to users via curve
    bool public migrated; // when true, trading disabled

    event Bought(address indexed buyer, uint256 ethIn, uint256 tokensOut);
    event Sold(address indexed seller, uint256 tokensIn, uint256 ethOut);
    event Migrated(
        address indexed to,
        uint256 tokensMigrated,
        uint256 ethMigrated
    );
    event Initialized(address indexed token, address indexed launcher);

    error TradingStopped();
    error ZeroAmount();
    error Slippage();

    constructor() {
        //treasury = _treasury;
        //superAdmin = msg.sender;
    }

    function initialize(
        address _token,
        uint256 _iVToken,
        uint256 _iVEth,
        uint256 _allocationA,
        uint256 _curveLimit,
        //address factoryAddress,
        //address _treasury,
        //uint96 _protocolFeeBps,
        address _creator
    ) external {
        require(!initialized, "Already initialized");
        require(token == address(0), "init once");
        require(_curveLimit >= factory.minCurveLimit(), "limit too low");
        require(_curveLimit <= factory.maxCurveLimit(), "limit too high");

        factory = IFactory(msg.sender);
        // Check with the factory if this token is already used
        require(!factory.tokenUsed(_token), "Token already in use");
        //require(_allocationA > 0, "allocationA=0");

        token = _token;
        vToken = _iVToken;
        vEth = _iVEth;
        allocationA = _allocationA;
        curveLimit = _curveLimit;
        creator = _creator;
        initialized = true;

        emit Initialized(_token, address(this));
    }

    // -------- BUY --------

    receive() external payable {
        //buy(0, referrerAddress); // minTokensOut = 0

        revert(); // ------------------------------------------------------
    }

    function buy(
        uint256 minTokensOut,
        address referrer
    ) public payable nonReentrant whenNotPaused {
        if (migrated) revert TradingStopped();
        uint256 ethIn = msg.value;
        if (ethIn == 0) revert ZeroAmount();

        // fees
        uint256 refFeeEth = (ethIn * factory.referralFeeBps()) / 10_000;
        uint256 protoEth = (ethIn * factory.platformFeeBps()) / 10_000;
        uint256 ethInEff = ethIn - refFeeEth - protoEth;

        // ===== VALIDATE REFERRER =====
        if (referrer != address(0) && referrer != msg.sender) {
            // Check if referrer actually holds some tokens before rewarding them
            if (CurveToken(token).balanceOf(referrer) > 0) {
                refFeeEth = (ethIn * factory.referralFeeBps()) / 10_000;
                // Referral fee will be sent later
            }
        }

        // compute tokensOut = vToken - k / (vEth + ethInEff)
        uint256 k = vToken * vEth;
        uint256 newVEth = vEth + ethInEff;
        uint256 tokensOut = vToken - (k / newVEth);

        require(tokensOut >= minTokensOut, "slippage too high");
        require(sold + tokensOut <= allocationA, "exceeds allocationA");

        // effects
        vEth = newVEth;
        vToken = vToken - tokensOut; // virtual token reserve decreases
        sold += tokensOut;

        // interactions
        CurveToken(token).mint(msg.sender, tokensOut);

        // send protocol fee & curve fee to treasury (can be split differently)
        // if (feeEth + protoEth > 0)
        //     payable(treasury).safeTransferETH(feeEth + protoEth);

        if (feeEth + protoEth > 0) {
            (bool sent, ) = payable(treasury).call{value: feeEth + protoEth}(
                ""
            );
            require(sent, "ETH transfer failed");
        }

        // check migration
        if (sold >= allocationA) {
            _migrate(); // or leave callable separately
        }

        emit Bought(msg.sender, ethIn, tokensOut);
    }

    // -------- SELL --------

    function sell(
        uint256 tokensIn,
        uint256 minEthOut
    ) external nonReentrant whenNotPaused {
        if (migrated) revert TradingStopped();
        if (tokensIn == 0) revert ZeroAmount();

        // receive tokens (curve burns them)
        CurveToken(token).burn(msg.sender, tokensIn);

        // fees on token side (optional), or apply fee on ETH out
        uint256 feeTokens = (tokensIn * tradeFeeBps) / 10_000;
        uint256 protoTokens = (tokensIn * protocolFeeBps) / 10_000;
        uint256 tokensEff = tokensIn - feeTokens - protoTokens;

        uint256 k = vToken * vEth;
        uint256 newVToken = vToken + tokensEff;
        uint256 ethOut = vEth - (k / newVToken);

        require(ethOut >= minEthOut, "slippage too high");
        require(address(this).balance >= ethOut, "insufficient ETH");

        // effects
        vToken = newVToken;
        vEth = vEth - ethOut;

        // send fees (if token-side fees are kept, mint to treasury; we burned above, so you might just collect ETH fees)
        if (protoTokens + feeTokens > 0) {
            CurveToken(token).mint(treasury, protoTokens + feeTokens);
        }

        // interactions
        //payable(msg.sender).safeTransferETH(ethOut);
        (bool sent, ) = payable(msg.sender).call{value: ethOut}("");
        require(sent, "ETH transfer failed");

        emit Sold(msg.sender, tokensIn, ethOut);
    }

    function getTokensOut(
        uint256 ethIn,
        bool isBuying
    ) public view returns (uint256 tokensOut) {
        if (ethIn == 0) return 0;

        if (isBuying) {
            // get fees from factory
            uint256 refFeeEth = (ethIn * factory.referralFeeBps()) / 10_000;
            uint256 protoEth = (ethIn * factory.platformFeeBps()) / 10_000;
            uint256 ethInEff = ethIn - refFeeEth - protoEth;

            // bonding curve math: tokensOut = vToken - k / (vEth + ethInEff)
            uint256 k = vToken * vEth;
            uint256 newVEth = vEth + ethInEff;
            tokensOut = vToken - (k / newVEth);
        } else {}
    }

    // -------- Migration --------

    function migrate() external nonReentrant whenNotPaused onlyOwner {
        require(!migrated, "already");
        require(sold >= allocationA, "not reached A");
        _migrate();
    }

    function _migrate() internal {
        migrated = true;

        // Compute M = (collateral_collected - F) / priceAtA
        // For simplicity here we just move remaining reserves and a portion of tokens to AMM.
        // Hook up to a MigrationManager to create the pair & seed liquidity.
        uint256 ethBal = address(this).balance;
        uint256 tokenBal = CurveToken(token).balanceOf(address(this)); // if you pre-minted supply to curve

        // TODO: call MigrationManager to set up pool & send LP to treasury/lock
        // emit event and leave funds in contract if manager not set
        emit Migrated(treasury, tokenBal, ethBal);
    }

    // -------- Admin --------

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setFactory(address _factory) external onlyOwner {
        factory = IFactory(_factory);
    }

    // GET FUNCTIONS
    function getTreasury() internal view returns (address) {
        return factory.treasury();
    }

    function getProtocolFeeBps() internal view returns (uint96) {
        return factory.protocolFeeBps();
    }

    function getLimits() public view returns (uint256 min, uint256 max) {
        min = factory.minCurveLimit();
        max = factory.maxCurveLimit();
    }
}
