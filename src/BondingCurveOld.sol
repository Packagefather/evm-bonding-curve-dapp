// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin-contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable2Step.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {CurveToken} from "./CurveToken.sol";
import "./IFactory.sol";
import "forge-std/console.sol";

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

    uint256 public tokensAfter;
    uint256 public tokensBefore;
    uint256 public newRaisedETH;

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

        vToken = (totalSupply * allocationA) / 10_000;
        //k = vETH * vToken; // Calculate constant k = vETH * vToken
        k = (vETH * vToken) / 1e18;

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

    // function buy(
    //     uint256 minTokensOut,
    //     address _referrer
    // ) public payable nonReentrant whenNotPaused {
    //     require(token != address(0), "No token address set");
    //     require(_referrer != msg.sender, "you cannot refer yourself");
    //     if (migrationTriggered) revert TradingStopped();

    //     uint256 incomingETH = msg.value;
    //     if (msg.value == 0) revert ZeroAmount();

    //     require(incomingETH > 0, "Insufficient ETH for tokens");
    //     //require(tokensSold + tokensToBuy <= vToken, "Exceeds allocation");

    //     // fees
    //     uint256 refFeeEth = (incomingETH * factory.referralFeeBps()) / 10_000;
    //     uint256 protoEth = (incomingETH * factory.protocolFeeBps()) / 10_000;
    //     uint256 ethInEff = incomingETH - refFeeEth - protoEth;

    //     // ===== VALIDATE AND REWARD REFERRER =====
    //     if (_referrer != address(0)) {
    //         // if referer has been set, send it to the referer
    //         // Check if referrer actually holds some tokens before rewarding them
    //         if (
    //             CurveToken(token).balanceOf(_referrer) >= minHoldingForReferrer
    //         ) {
    //             // add it to the referrers mapping
    //             if (referrerOf[msg.sender] == address(0)) {
    //                 referrerOf[msg.sender] = _referrer;
    //             }

    //             referralRewards[referrerOf[msg.sender]] += refFeeEth;
    //             emit ReferralBonusAwarded(referrerOf[msg.sender], refFeeEth);
    //         } else {
    //             // send it tot the admin fee account
    //             (bool sentA, ) = payable(factory.treasury()).call{
    //                 value: refFeeEth
    //             }("");
    //             require(sentA, "BNB transfer failed");

    //             emit ReferralBonusAwarded(factory.treasury(), refFeeEth);
    //         }
    //     } else {
    //         // send it to the admin fee account
    //         (bool sentB, ) = payable(factory.treasury()).call{value: refFeeEth}(
    //             ""
    //         );
    //         require(sentB, "BNB transfer failed");

    //         emit ReferralBonusAwarded(factory.treasury(), refFeeEth);
    //     }

    //     // CREDIT TREASURY WITH PROTOCOL FEES
    //     (bool sentC, ) = payable(factory.treasury()).call{value: protoEth}("");
    //     require(sentC, "BNB transfer failed");

    //     // Bonding curve maths starts here

    //     // New total ETH raised if this purchase goes through
    //     newRaisedETH = raisedETH + ethInEff;

    //     // Calculate tokens sold at newRaisedETH (using bonding curve)
    //     // Calculate how many tokens would be sold at this new point
    //     tokensAfter = tokensSoldAt(newRaisedETH);
    //     tokensBefore = tokensSoldAt(raisedETH);

    //     uint256 tokensToBuy = tokensAfter - tokensBefore;

    //     // If it exceeds what's left, cap it and recalculate ETH needed
    //     uint256 tokensAvailable = vToken - tokensSold;

    //     if (tokensToBuy > tokensAvailable) {
    //         tokensToBuy = tokensAvailable;
    //     }
    //     // Compute the ETH needed to buy exactly these remaining tokens
    //     uint256 newTokensSold = tokensSold + tokensToBuy;
    //     uint256 denominator = vToken - newTokensSold; // y = vToken - tokensSold

    //     require(denominator > 0, "Denominator zero");

    //     // uint256 ethTarget = (k * 1e18) / denominator;
    //     // require(ethTarget >= vETH * 1e18, "Invalid curve state");

    //     uint256 ethTarget = (k * 1e18) / denominator; // 18 decimals scaled up to keep precision
    //     require(ethTarget >= vETH, "Invalid curve state");

    //     // uint256 requiredRaisedETH = (ethTarget - (vETH * 1e18)) / 1e18; // Unscale

    //     // uint256 ethToAccept = requiredRaisedETH - raisedETH;

    //     uint256 requiredRaisedETH = ethTarget - vETH; // both 18 decimals, result 18 decimals
    //     uint256 ethToAccept = requiredRaisedETH - raisedETH; // assuming raisedETH is 18 decimals too

    //     // Cap ethToAccept to msg.value just in case
    //     if (ethToAccept > msg.value) {
    //         ethToAccept = msg.value;
    //     }

    //     // Refund excess
    //     uint256 refund = msg.value - ethToAccept;
    //     if (refund > 0) {
    //         payable(msg.sender).transfer(refund);
    //     }

    //     // Update state with adjusted ETH and tokens
    //     raisedETH += ethToAccept;
    //     tokensSold += tokensToBuy;

    //     // Transfer tokens
    //     // bool sent = CurveToken(token).transfer(msg.sender, 50);
    //     // require(!sent, "Token transfer failed");

    //     SafeTransferLib.safeTransfer(token, msg.sender, tokensToBuy);

    //     if (tokensSold >= vToken || raisedETH >= curveLimit) {
    //         migrationTriggered = true;
    //         emit MigrationTriggered(raisedETH, tokensSold);
    //     }

    //     console.log("Hello world");
    //     console.log("tokensToBuy in contract:", tokensToBuy);
    //     console.log("ethToAccept in contract:", ethToAccept);
    //     emit Bought(msg.sender, ethToAccept, tokensToBuy);

    //     require(tokensToBuy >= minTokensOut, "slippage too high");
    // }

    function buy(
        uint256 minTokensOut,
        address _referrer
    ) public payable nonReentrant whenNotPaused {
        require(token != address(0), "No token address set");
        require(_referrer != msg.sender, "You cannot refer yourself");
        if (migrationTriggered) revert TradingStopped();

        uint256 incomingETH = msg.value;
        if (incomingETH == 0) revert ZeroAmount();

        // === FEES ===
        uint256 refFeeEth = (incomingETH * factory.referralFeeBps()) / 10_000;
        uint256 protoEth = (incomingETH * factory.protocolFeeBps()) / 10_000;
        uint256 ethInEff = incomingETH - refFeeEth - protoEth;

        // === REFERRAL HANDLING ===
        if (_referrer != address(0)) {
            if (
                CurveToken(token).balanceOf(_referrer) >= minHoldingForReferrer
            ) {
                if (referrerOf[msg.sender] == address(0)) {
                    referrerOf[msg.sender] = _referrer;
                }

                referralRewards[referrerOf[msg.sender]] += refFeeEth;
                emit ReferralBonusAwarded(referrerOf[msg.sender], refFeeEth);
            } else {
                (bool sentA, ) = payable(factory.treasury()).call{
                    value: refFeeEth
                }("");
                require(sentA, "ETH transfer failed");
                emit ReferralBonusAwarded(factory.treasury(), refFeeEth);
            }
        } else {
            (bool sentB, ) = payable(factory.treasury()).call{value: refFeeEth}(
                ""
            );
            require(sentB, "ETH transfer failed");
            emit ReferralBonusAwarded(factory.treasury(), refFeeEth);
        }

        // === PROTOCOL FEE ===
        (bool sentC, ) = payable(factory.treasury()).call{value: protoEth}("");
        require(sentC, "ETH transfer failed");

        // === CURVE CALCULATION ===
        newRaisedETH = raisedETH + ethInEff;

        tokensAfter = tokensSoldAt(newRaisedETH);
        tokensBefore = tokensSoldAt(raisedETH);

        uint256 tokensToBuy = tokensAfter - tokensBefore;

        uint256 tokensAvailable = vToken - tokensSold;
        if (tokensToBuy > tokensAvailable) {
            tokensToBuy = tokensAvailable;
        }

        uint256 newTokensSold = tokensSold + tokensToBuy;
        uint256 denominator = vToken - newTokensSold;
        require(denominator > 0, "Denominator zero");

        uint256 ethTarget = (k * 1e18) / denominator;
        require(ethTarget >= raisedETH, "Invalid curve state");

        uint256 ethToAccept = ethTarget - raisedETH;
        console.log("Eth to accept A:", ethToAccept);

        if (ethToAccept > msg.value) {
            ethToAccept = msg.value;
        }
        console.log("Eth to accept B:", ethToAccept);
        // 6.612500000000000000
        uint256 refund = msg.value - ethToAccept;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        raisedETH += ethToAccept;
        tokensSold += tokensToBuy;

        SafeTransferLib.safeTransfer(token, msg.sender, tokensToBuy);

        if (tokensSold >= vToken || raisedETH >= curveLimit) {
            migrationTriggered = true;
            emit MigrationTriggered(raisedETH, tokensSold);
        }

        require(tokensToBuy >= minTokensOut, "Slippage too high");
        emit Bought(msg.sender, ethToAccept, tokensToBuy);
    }

    function tokensSoldAt(uint256 x) public view returns (uint256) {
        require(vETH + x > 0, "Denominator zero");

        uint256 denominator = vETH + x; // (x0 + current ETH raised)
        uint256 division = (k * 1e18) / denominator; // scale for precision

        // tokens sold = vToken - k / (vETH + x)
        return vToken > division ? vToken - division : 0;
    }

    // 972,974,013
    // -------- SELL --------

    function sell(
        uint256 tokensToSell,
        uint256 minEthOut
    ) external nonReentrant whenNotPaused {
        if (tokensToSell == 0) revert ZeroAmount();
        require(tokensSold >= tokensToSell, "Not enough tokens sold");
        if (migrationTriggered) revert TradingStopped();

        uint256 tokensSoldBefore = tokensSold;
        uint256 tokensSoldAfter = tokensSoldBefore - tokensToSell;
        require(vToken > tokensSoldAfter, "Invalid tokens sold after");

        // === CURVE CALCULATION ===
        uint256 ethBefore = (k * 1e18) / (vToken - tokensSoldBefore); // scaled
        uint256 ethAfter = (k * 1e18) / (vToken - tokensSoldAfter); // scaled

        require(ethAfter >= raisedETH, "Invalid curve");

        uint256 ethToReturn = ethBefore - ethAfter;
        console.log(
            "ethbefore and ethafter: ",
            ethBefore,
            ethAfter,
            ethToReturn
        );
        //require(ethToReturn >= minEthOut, "Slippage too high");
        // 25.975000000000000000 25.874091044924793306

        // ethToReturn = 0.100908955075206694
        // effectiveEth = 0.068618089451140553
        // === EFFECTS ===
        tokensSold = tokensSoldAfter;
        raisedETH -= ethToReturn;

        bool received = CurveToken(token).transferFrom(
            msg.sender,
            address(this),
            tokensToSell
        );
        require(received, "Token transfer failed");

        // === FEES ===
        uint256 antifudFeeEth = (ethToReturn * factory.antifiludFeeBps()) /
            10_000;
        uint256 protoEth = (ethToReturn * factory.protocolFeeBps()) / 10_000;
        uint256 ethInEff = ethToReturn - antifudFeeEth - protoEth;

        uint256 antifudToLauncher = (antifudFeeEth *
            factory.antifiludLauncherQuotaBps()) / 10_000;
        uint256 antifudToCurve = antifudFeeEth - antifudToLauncher;

        console.log(
            "Effective eth to give user and minEThOut:",
            ethInEff,
            minEthOut
        );

        require(ethInEff >= minEthOut, "Slippage too high");

        bonusLiquidity += antifudToCurve;
        creatorsRewards[creator] += antifudToLauncher;

        payable(msg.sender).transfer(ethInEff);
        emit Sold(msg.sender, ethToReturn, tokensToSell);
    }

    // 68618089451140553
    // 68618089451140553
    // 68618089451140553
    /*
    function sell(
        uint256 tokensToSell,
        uint256 minEthOut
    ) external nonReentrant whenNotPaused {
        if (tokensToSell == 0) revert ZeroAmount();
        require(tokensSold >= tokensToSell, "Not enough tokens sold");
        if (migrationTriggered) revert TradingStopped();

        uint256 tokensSoldBefore = tokensSold;
        uint256 tokensSoldAfter = tokensSoldBefore - tokensToSell;

        // Avoid division by zero
        require(vToken > tokensSoldAfter, "Invalid tokens sold after");

        // ETH before sale
        uint256 ethBefore = (k * 1e18) / (vToken - tokensSoldBefore); // scaled
        require(ethBefore >= vETH, "Invalid curve");

        ethBefore = ethBefore - vETH; // 18 decimals
        // No division here unless you need to convert to wei or another unit later

        ethBefore = ethBefore - (vETH * 1e18); // still scaled
        ethBefore = ethBefore / 1e18;

        // ETH after sale
        uint256 ethAfter = (k * 1e18) / (vToken - tokensSoldAfter); // 18 decimals
        require(ethAfter >= vETH, "Invalid curve");

        ethAfter = ethAfter - vETH; // 18 decimals

        // ETH to return = before - after
        uint256 ethToReturn = ethBefore - ethAfter; // 18 decimals

        // console.log("tokensToBuy:", tokensToBuy);
        // console.log("minTokensOut:", minTokensOut);

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
        // fees
        uint256 antifiludFeeEth = (ethToReturn * factory.antifiludFeeBps()) /
            10_000;
        uint256 protoEth = (ethToReturn * factory.protocolFeeBps()) / 10_000;
        uint256 ethInEff = ethToReturn - antifiludFeeEth - protoEth;

        uint256 antifudToLauncher = (antifiludFeeEth *
            factory.antifiludLauncherQuotaBps()) / 10_000;

        uint256 antifudToCurve = antifiludFeeEth - antifudToLauncher;
        bonusLiquidity += antifudToCurve; // keep the antifud portion in the curve for liquidity boost at migration
        creatorsRewards[creator] += antifudToLauncher; // save the portion for the creator

        payable(msg.sender).transfer(ethInEff);

        emit Sold(msg.sender, ethToReturn, tokensToSell);
    }

    */
    function getTokensOut(
        uint256 ethIn
    ) external view returns (uint256 tokensOut) {
        if (migrationTriggered) revert TradingStopped();
        require(ethIn > 0, "Zero ETH in");

        // calculate the fees
        uint256 refFeeEth = (ethIn * factory.referralFeeBps()) / 10_000;
        uint256 protoEth = (ethIn * factory.protocolFeeBps()) / 10_000;
        uint256 ethInEff = ethIn - refFeeEth - protoEth;

        // Calculate new raisedETH after this buy
        uint256 newRaised = raisedETH + ethInEff;

        uint256 denominatorBefore = vETH + raisedETH; // 18 decimals
        uint256 denominatorAfter = vETH + newRaised; // 18 decimals

        uint256 tokensBeforeSale = vToken - (k * 1e18) / denominatorBefore;
        uint256 tokensAfterSale = vToken - (k * 1e18) / denominatorAfter;

        tokensOut = tokensAfterSale > tokensBeforeSale
            ? tokensAfterSale - tokensBeforeSale
            : 0;

        // Clamp to remaining tokens (in case of nearing curve limit)
        uint256 tokensAvailable = vToken - tokensSold;
        if (tokensOut > tokensAvailable) {
            tokensOut = tokensAvailable;
        }
    }

    /*
    function getMinEthOut(
        uint256 tokensIn
    ) external view returns (uint256 ethOut) {
        require(tokensIn > 0, "Zero tokens in");
        //require(!migrationTriggered, "Trading stopped");
        require(tokensIn <= tokensSold, "Not enough tokens sold yet");

        // tokensSold BEFORE selling
        uint256 tokensBeforeSale = tokensSold;

        // tokensSold AFTER selling (going backward on curve)
        uint256 tokensAfterSale = tokensBeforeSale - tokensIn;

        // raisedETH BEFORE selling
        uint256 ethBefore = raisedETH;

        // ETH raised if tokensAfter was the sold amount (solve for ETH where y = vToken - tokensAfter)
        uint256 denominatorAfter = vToken - tokensAfterSale;
        require(denominatorAfter > 0, "Invalid denominator");

        uint256 ethTarget = (k * 1e18) / denominatorAfter;
        require(ethTarget >= vETH, "Invalid curve state");
        //require(ethTarget >= vETH * 1e18, "Invalid curve state");

        //uint256 newRaised = (ethTarget - (vETH * 1e18)) / 1e18;
        uint256 newRaised = ethTarget - vETH;

        uint256 ethOutBeforeFee = ethBefore - newRaised;

        // Implement the fees on the sell side
        uint256 protoEth = (ethOutBeforeFee * factory.protocolFeeBps()) /
            10_000;
        uint256 antifudEth = (ethOutBeforeFee * factory.antifiludFeeBps()) /
            10_000;
        ethOut = ethOutBeforeFee - protoEth - antifudEth;

        console.log("ethOut before fees:", ethOutBeforeFee);
        console.log("ethOut after fees:", ethOut);
        console.log("protoFee:", protoEth);
        console.log("antifudFee:", antifudEth);
    }

    */

    function getMinEthOut(
        uint256 tokensIn
    ) external view returns (uint256 ethOut) {
        require(tokensIn > 0, "Zero tokens in");
        require(tokensIn <= tokensSold, "Not enough tokens sold yet");

        uint256 tokensBeforeSell = tokensSold;
        uint256 tokensAfterSell = tokensBeforeSell - tokensIn;

        uint256 ethBefore = (k * 1e18) / (vToken - tokensBeforeSell);
        uint256 ethAfter = (k * 1e18) / (vToken - tokensAfterSell);
        uint256 ethOutBeforeFee = ethBefore - ethAfter;

        uint256 protoEth = (ethOutBeforeFee * factory.protocolFeeBps()) /
            10_000;
        uint256 antifudEth = (ethOutBeforeFee * factory.antifiludFeeBps()) /
            10_000;
        ethOut = ethOutBeforeFee - protoEth - antifudEth;
    }

    // 0.127698724735322427

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

    function getLiquiditySeedAmounts()
        external
        view
        returns (uint256 ethToSeed, uint256 tokensToSeed, uint256 lastPrice)
    {
        // Ensure we don't divide by zero
        require(tokensSold < vToken, "All tokens sold");

        // Calculate last price (ETH per token) at the end of bonding curve
        // This is the marginal price of the next token
        lastPrice = (k * 1e18) / (vToken - tokensSold); // 18 decimals (ETH per token)

        // ETH to seed is total ETH raised
        ethToSeed = raisedETH;

        // Calculate token amount that will match ethToSeed at this price
        // tokens = eth / price → scaled for 18 decimals
        tokensToSeed = (ethToSeed * 1e18) / lastPrice;
    }

    // -------- Admin --------

    function pause() external onlySuperAdmin {
        _pause();
    }

    function unpause() external onlySuperAdmin {
        _unpause();
    }

    modifier onlySuperAdmin() {
        require(msg.sender == factory.superAdmin(), "Not super admin");
        _;
    }

    // function setFactory(address _factory) external onlySuperAdmin {
    //     factory = IFactory(_factory);
    // }

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

    function getOwner() public pure returns (address owner) {
        return owner;
    }
}
