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
    mapping(address => uint256) public referralRewards;
    mapping(address => uint256) public creatorsRewards;

    uint256 public allocationA; // ~80% of supply
    uint256 public curveLimit; // FDV at A (for sanity checks)
    uint256 public minHoldingForReferrer; // min tokens a referrer must hold to get referral fees

    //Immutatble state
    uint256 public vToken; // starts at iVToken
    uint256 public vETH; // starts at ivETH
    uint256 public k;
    uint256 public raisedETH; // total ETH raised so far (wei)
    uint256 public tokensSold; // tokens sold via bonding curve (18 decimals)
    uint256 public totalSupply; // e.g. 1_000_000_000e18
    bool public migrationTriggered;

    // tokens allocated to bonding curve (80% of totalSupply)
    // curve constant

    uint256 public bonusLiquidity; // e.g. 50% of antifud fee funds, added at migration

    // Mutable state
    //uint256 public sold; // total tokens sold to users via curve
    //bool public migrated; // when true, trading disabled

    event Bought(address indexed buyer, uint256 ethIn, uint256 tokensOut);
    event Sold(address indexed seller, uint256 tokensIn, uint256 ethOut);
    // event Migrated(
    //     address indexed to,
    //     uint256 tokensMigrated,
    //     uint256 ethMigrated
    // );
    event Initialized(address indexed token, address indexed launcher);
    event ReferralBonusAwarded(address indexed referrer, uint256 amount);
    event MigrationTriggered(uint256 raisedETH, uint256 tokensSold);

    error TradingStopped();
    error ZeroAmount();
    error Slippage();

    // constructor() {
    //     //treasury = _treasury;
    //     //superAdmin = msg.sender;
    // }

    function initialize(
        address _token,
        //uint256 _iVToken,
        uint256 _allocationPercent,
        uint256 _curveLimit,
        address _creator,
        uint256 _minHoldingForReferrer
    ) external {
        require(!initialized, "Already initialized");
        require(token == address(0), "init once");
        require(_token != address(0), "zero token");

        factory = IFactory(msg.sender);

        require(_curveLimit >= factory.minCurveLimitEth(), "limit too low");
        require(_curveLimit <= factory.maxCurveLimitEth(), "limit too high");
        // Check with the factory if this token is already used
        require(!factory.tokenUsed(_token), "Token already in use");
        require(
            _allocationPercent > 0 && _allocationPercent <= 100_000,
            "Allocation % invalid"
        );

        token = _token;
        totalSupply = factory.totalSupply();
        vETH = factory.virtualETH();
        allocationA = _allocationPercent;
        curveLimit = _curveLimit;
        creator = _creator;
        minHoldingForReferrer = _minHoldingForReferrer;

        vToken = (totalSupply * _allocationPercent) / 100_000;
        k = (vToken * (vETH + curveLimit)) / 1e18;

        raisedETH = 0;
        tokensSold = 0;
        migrationTriggered = false;

        initialized = true;

        emit Initialized(_token, address(this));
    }

    // ----------- Bonding Curve math -----------

    // Current price p(x) = (vETH + x)^2 / k, scaled to 1e18 decimals
    function currentPrice() public view returns (uint256) {
        uint256 numerator = (vETH + raisedETH) * (vETH + raisedETH);
        return (numerator * 1e18) / k;
    }

    // tokens sold at given ETH raised x: T(x) = vToken - k / (vETH + x)
    function tokensSoldAt(uint256 x) public view returns (uint256) {
        require(vETH + x > 0, "Denominator zero");
        uint256 denominator = vETH + x;
        uint256 division = (k * 1e18) / denominator;
        return vToken > division ? vToken - division : 0;
    }

    // Tokens to mint for ethAmount invested
    function tokensForETH(uint256 ethAmount) public view returns (uint256) {
        uint256 afterTokens = tokensSoldAt(raisedETH + ethAmount);
        uint256 beforeTokens = tokensSoldAt(raisedETH);
        require(afterTokens >= beforeTokens, "Math underflow");
        return afterTokens - beforeTokens;
    }

    // -------- BUY --------

    receive() external payable {
        //buy(0, referrerAddress); // minTokensOut = 0

        revert(); // ------------------------------------------------------
    }

    function buy(
        uint256 minTokensOut,
        address _referrer
    ) public payable nonReentrant whenNotPaused {
        require(_referrer != msg.sender, "you cannot refer yourself");
        if (migrationTriggered) revert TradingStopped();

        uint256 incomingETH = msg.value;
        if (msg.value == 0) revert ZeroAmount();

        require(incomingETH > 0, "Insufficient ETH for tokens");
        //require(tokensSold + tokensToBuy <= vToken, "Exceeds allocation");

        // fees
        uint256 refFeeEth = (incomingETH * factory.referralFeeBps()) / 10_000;
        uint256 protoEth = (incomingETH * factory.platformFeeBps()) / 10_000;
        uint256 ethInEff = incomingETH - refFeeEth - protoEth;

        // ===== VALIDATE AND REWARD REFERRER =====
        if (_referrer != address(0)) {
            // if referer has been set, send it to the referer
            // Check if referrer actually holds some tokens before rewarding them
            if (
                CurveToken(token).balanceOf(_referrer) >= minHoldingForReferrer
            ) {
                // add it to the referrers mapping
                if (referrerOf[msg.sender] == address(0)) {
                    referrerOf[msg.sender] = _referrer;
                }

                referralRewards[referrerOf[msg.sender]] += refFeeEth;
                emit ReferralBonusAwarded(referrerOf[msg.sender], refFeeEth);
            } else {
                // send it tot the admin fee account
                (bool sentA, ) = payable(factory.treasury()).call{
                    value: refFeeEth
                }("");
                require(sentA, "BNB transfer failed");

                emit ReferralBonusAwarded(factory.treasury(), refFeeEth);
            }
        } else {
            // send it to the admin fee account
            (bool sentB, ) = payable(factory.treasury()).call{value: refFeeEth}(
                ""
            );
            require(sentB, "BNB transfer failed");

            emit ReferralBonusAwarded(factory.treasury(), refFeeEth);
        }

        // CREDIT TREASURY WITH PROTOCOL FEES
        (bool sentC, ) = payable(factory.treasury()).call{value: protoEth}("");
        require(sentC, "BNB transfer failed");

        uint256 tokensToBuy = tokensForETH(ethInEff);

        // Lets check if user is to buy what will exceed the curve limit
        uint256 tokensAvailable = vToken - tokensSold;
        uint256 ethToAccept = msg.value;

        if (tokensToBuy > tokensAvailable) {
            tokensToBuy = tokensAvailable;

            // Calculate ETH needed to buy remaining tokensAvailable
            uint256 newTokensSold = tokensSold + tokensAvailable;

            uint256 denominator = vToken - newTokensSold;
            require(denominator > 0, "Denominator zero");

            // careful with scaling, example:
            //uint256 ethAfter = ((k * 1e18) / (vToken - newTokensSold));
            uint256 ethTarget = (k * 1e18) / denominator; // scaled
            require(ethTarget >= vETH * 1e18, "vETH error");

            uint256 newRaisedETH = ethTarget - (vETH * 1e18); // still scaled
            newRaisedETH = newRaisedETH / 1e18; // unscale

            ethToAccept = newRaisedETH - raisedETH;

            //uint256 deltaETH = ethAfter - raisedETH;

            if (ethToAccept > msg.value) {
                ethToAccept = msg.value; // safety
            }

            // ethToAccept = deltaETH;
        }

        // we have it here so it can check for that edge case above,
        //where user tries to buy more than available
        require(tokensToBuy >= minTokensOut, "slippage too high");

        // Update state
        raisedETH += ethToAccept;
        tokensSold += tokensToBuy;

        // interactions
        bool send = CurveToken(token).transfer(msg.sender, tokensToBuy);
        require(send, "Token transfer failed");
        emit Bought(msg.sender, ethToAccept, tokensToBuy);

        // Refund extra ETH if any
        if (msg.value > ethToAccept) {
            payable(msg.sender).transfer(msg.value - ethToAccept);
        }

        if (tokensSold >= vToken || raisedETH >= curveLimit) {
            migrationTriggered = true;
            emit MigrationTriggered(raisedETH, tokensSold);
        }
    }

    // -------- SELL --------
    /*
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

        uint256 k = vToken * vETH;
        uint256 newVToken = vToken + tokensEff;
        uint256 ethOut = vETH - (k / newVToken);

        require(ethOut >= minEthOut, "slippage too high");
        require(address(this).balance >= ethOut, "insufficient ETH");

        // effects
        vToken = newVToken;
        vETH = vETH - ethOut;

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
*/
    /*
    function swapQuote(
        uint256 ethIn,
        bool isBuying
    ) public view returns (uint256 tokensOut) {
        if (ethIn == 0) return 0;

        if (isBuying) {
            // get fees from factory
            uint256 refFeeEth = (ethIn * factory.referralFeeBps()) / 10_000;
            uint256 protoEth = (ethIn * factory.platformFeeBps()) / 10_000;
            uint256 ethInEff = ethIn - refFeeEth - protoEth;

            // bonding curve math: tokensOut = vToken - k / (vETH + ethInEff)
            return tokensOut = _getTokensOut(ethInEff);
        } else {
            //selling
            uint256 ethOut = _getEthOut(ethIn);

            uint256 protoEth = (ethOut * factory.platformFeeBps()) / 10_000;
            uint256 antifudEth = (ethOut * factory.antiFudPercentage()) /
                10_000;
            uint256 ethOutEff = ethOut - protoEth - antifudEth;

            return ethOutEff;
        }
    }
*/
    // function _getTokensOut(
    //     uint256 ethInEff
    // ) internal view returns (uint256 tokensOut) {
    //     uint256 k = vToken * vETH;
    //     uint256 newvETH = vETH + ethInEff;
    //     tokensOut = vToken - (k / newvETH);
    // }

    // function _getEthOut(
    //     uint256 tokensIn
    // ) internal view returns (uint256 ethOut) {
    //     uint256 k = vToken * vETH;
    //     uint256 newVToken = vToken + tokensIn;
    //     ethOut = vETH - (k / newVToken);
    // }

    /*
    function calculateTokensOut(
        uint256 amountIn,
        bool isBuying
    ) internal returns (uint256 amount_out) {
        // uint256 k = vToken * vETH;
        // uint256 newvETH = vETH + amountIn;
        // tokensOut = vToken - (k / newvETH);
        uint256 k = vToken * vETH;
        //uint256 tokensOut;
        //uint256 ethOut;
        if (isBuying) {
            //we calculate fees before passing effETH in here

            uint256 newvETH = vETH + amountIn;
            amount_out = vToken - (k / newvETH);

            //updating the virtual and real reserves
            vETH = newvETH;
            vToken -= amount_out; // virtual token reserve decreases
            rEth += amountIn; // real ETH reserve increases
            rToken -= amount_out; // real token reserve decreases
            //return (vToken, vETH, amount_out);
            return amount_out;
        } else {
            // we claculate fee inside here

            uint256 vTOKEN_new = vToken + amountIn;
            uint256 vETH_new = k / vTOKEN_new;

            uint256 eth_out = vETH - vETH_new;

            //calculate the fees
            uint256 protoEth = (eth_out * factory.platformFeeBps()) / 10_000;
            uint256 antifudEth = (eth_out * factory.antiFudPercentage()) /
                10_000;
            uint256 new_eth_out = eth_out - protoEth - antifudEth; // what will go to the seller

            // updating the virtual and real reserves
            vToken = vTOKEN_new;
            rToken += amountIn; // real token reserve increases
            vETH -= eth_out; // virtual ETH reserve decreases
            rEth -= eth_out; // real ETH reserve decreases

            //transfer fees accordingly
            if (protoEth > 0) {
                (bool sent, ) = payable(factory.treasury()).call{
                    value: protoEth
                }("");
                require(sent, "BNB transfer failed");
            }
            if (antifudEth > 0) {
                uint256 toLauncher = (antifudEth *
                    factory.antifiludLauncherQuotaBps()) / 10_000;
                uint256 toCurve = antifudEth - toLauncher;

                bonusLiquidity += toCurve; // keep the antifud portion in the curve for liquidity boost at migration
                creatorsRewards[creator] += toLauncher; // save the portion for the creator to withdraw later
            }

            return new_eth_out;
        }
    }
*/
    // -------- Migration --------
    /*
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
*/
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
        min = factory.minCurveLimitEth();
        max = factory.maxCurveLimitEth();
    }
}
