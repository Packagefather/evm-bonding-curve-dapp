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
    error vTokensExceeded();

    // constructor() {
    //     //treasury = _treasury;
    //     //superAdmin = msg.sender;
    // }

    function initialize(
        address _token,
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

        token = _token;
        totalSupply = factory.totalSupply();
        curveLimit = _curveLimit; // curveLimit set by user, in ETH (or SOL)
        vETH = curveLimit / 4; // Calculate initial virtual ETH reserve (vETH) based on curveLimit
        allocationA = factory.fixedAllocationPercent();

        creator = _creator;
        minHoldingForReferrer = _minHoldingForReferrer;

        vToken = (totalSupply * allocationA) / 100_000;
        k = vETH * vToken; // Calculate constant k = vETH * vToken

        raisedETH = 0;
        tokensSold = 0;
        migrationTriggered = false;

        initialized = true;

        emit Initialized(_token, address(this));
    }

    // ----------- Bonding Curve math -----------

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

        // Bonding curve maths starts here

        // New total ETH raised if this purchase goes through
        uint256 newRaisedETH = raisedETH + ethInEff;

        // Calculate tokens sold at newRaisedETH (using bonding curve)
        // Calculate how many tokens would be sold at this new point
        uint256 tokensAfter = tokensSoldAt(newRaisedETH);
        uint256 tokensBefore = tokensSoldAt(raisedETH);

        uint256 tokensToBuy = tokensAfter - tokensBefore;

        // If it exceeds what's left, cap it and recalculate ETH needed
        uint256 tokensAvailable = vToken - tokensSold;

        if (tokensToBuy > tokensAvailable) {
            tokensToBuy = tokensAvailable;

            // Compute the ETH needed to buy exactly these remaining tokens
            uint256 newTokensSold = tokensSold + tokensToBuy;
            uint256 denominator = vToken - newTokensSold; // y = vToken - tokensSold

            require(denominator > 0, "Denominator zero");

            uint256 ethTarget = (k * 1e18) / denominator;
            require(ethTarget >= vETH * 1e18, "Invalid curve state");

            uint256 requiredRaisedETH = (ethTarget - (vETH * 1e18)) / 1e18; // Unscale

            uint256 ethToAccept = requiredRaisedETH - raisedETH;

            // Cap ethToAccept to msg.value just in case
            if (ethToAccept > msg.value) {
                ethToAccept = msg.value;
            }

            // Refund excess
            uint256 refund = msg.value - ethToAccept;
            if (refund > 0) {
                payable(msg.sender).transfer(refund);
            }

            // Update state with adjusted ETH and tokens
            raisedETH += ethToAccept;
            tokensSold += tokensToBuy;

            // Transfer tokens
            bool sent = CurveToken(token).transfer(msg.sender, tokensToBuy);
            require(sent, "Token transfer failed");

            if (tokensSold >= vToken || raisedETH >= curveLimit) {
                migrationTriggered = true;
                emit MigrationTriggered(raisedETH, tokensSold);
            }

            emit Bought(msg.sender, ethToAccept, tokensToBuy);
        }

        require(tokensToBuy >= minTokensOut, "slippage too high");
    }

    function tokensSoldAt(uint256 x) public view returns (uint256) {
        require(vETH + x > 0, "Denominator zero");

        uint256 denominator = vETH + x; // (x0 + current ETH raised)
        uint256 division = (k * 1e18) / denominator; // scale for precision

        // tokens sold = vToken - k / (vETH + x)
        return vToken > division ? vToken - division : 0;
    }

    // -------- SELL --------

    function sell(
        uint256 tokensToSell,
        uint256 minEthOut
    ) external nonReentrant whenNotPaused {
        if (tokensToSell == 0) revert ZeroAmount();
        require(tokensSold >= tokensToSell, "Not enough tokens sold");

        uint256 tokensSoldBefore = tokensSold;
        uint256 tokensSoldAfter = tokensSoldBefore - tokensToSell;

        // Avoid division by zero
        require(vToken > tokensSoldAfter, "Invalid tokens sold after");

        // ETH before sale
        uint256 ethBefore = (k * 1e18) / (vToken - tokensSoldBefore); // scaled
        require(ethBefore >= vETH * 1e18, "Invalid curve");

        ethBefore = ethBefore - (vETH * 1e18); // still scaled
        ethBefore = ethBefore / 1e18;

        // ETH after sale
        uint256 ethAfter = (k * 1e18) / (vToken - tokensSoldAfter); // scaled
        require(ethAfter >= vETH * 1e18, "Invalid curve");

        ethAfter = ethAfter - (vETH * 1e18); // still scaled
        ethAfter = ethAfter / 1e18;

        // ETH to return = before - after
        uint256 ethToReturn = ethBefore - ethAfter;

        require(ethToReturn >= minEthOut, "Slippage too high");

        // Effects
        tokensSold = tokensSoldAfter;
        raisedETH -= ethToReturn;

        // Interactions
        bool received = CurveToken(token).transferFrom(
            msg.sender,
            address(this),
            tokensToSell
        );
        require(received, "Token transfer failed");

        // calculate the fees and send the right amount to the user
        payable(msg.sender).transfer(ethToReturn);

        emit Sold(msg.sender, ethToReturn, tokensToSell);
    }

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
