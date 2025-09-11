// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IPancakeRouter02.sol";

import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin-contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable2Step.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {CurveToken} from "./CurveToken.sol";
import "./interfaces/IFactory.sol";
import "forge-std/console.sol";

contract BondingCurve is ReentrancyGuard, Pausable, Ownable(msg.sender) {
    using SafeTransferLib for address;

    IFactory public factory;

    IPancakeFactory public pancakeFactory;
    IPancakeRouter02 public lpRouter;

    address public token;
    bool private initialized;

    address public referrer;
    address public creator;
    mapping(address => address) public referrerOf;
    mapping(address => uint256) public referralRewards;
    mapping(address => uint256) public creatorsRewards;

    uint256 public allocationA; // ~80% of supply.
    uint256 public curveLimit; // FDV at A (for sanity checks)
    uint256 public minHoldingForReferrer; // min tokens a referrer must hold to get referral fees

    //Immutatble state
    uint256 public vToken; // starts at iVToken
    uint256 public vETH; // starts at ivETH.
    uint256 public k;
    uint256 public raisedETH; // total ETH raised so far (wei)
    uint256 public tokensSold; // tokens sold via bonding curve (18 decimals)
    uint256 public totalSupply; // e.g. 1_000_000_000e18
    bool public migrationTriggered;
    bool public lpMigrated;

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
    event LPMigrated(
        uint256 tokensToLP,
        uint256 netETH,
        uint256 priceAtMigration
    );

    error TradingStopped();
    error ZeroAmount();
    error Slippage();
    error vTokensExceeded();

    uint256 public tokensAfter;
    uint256 public tokensBefore;

    //uint256 public newRaisedETH;

    // constructor() {
    //     //treasury = _treasury;
    //     //superAdmin = msg.sender;
    // }

    function initialize(
        address _token,
        uint256 _curveLimit,
        address _creator,
        uint256 _minHoldingForReferrer,
        uint256 _vETH
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
        //vETH = curveLimit / 4; // Calculate initial virtual ETH reserve (vETH) based on curveLimit
        allocationA = factory.fixedAllocationPercent();
        //uint256 allocationB = factory.fixedAllocationOfVToken(); // 99.99% of vToken is what we want to sell
        vETH = _vETH; //44 * 1e18; //calculateVETH(_curveLimit, allocationB);
        console.log("vETH at init:", vETH);
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

    function calculateVETH(
        uint256 _curveLimit,
        uint256 sellPercentBps
    ) internal pure returns (uint256) {
        require(sellPercentBps < 10_000, "Can't sell 100%");
        uint256 p = (sellPercentBps * 1e18) / 10_000;
        uint256 denominator = (1e18 * 1e18) / (1e18 - p) - 1e18;
        return (_curveLimit * 1e18) / denominator;
    }

    function buy(
        uint256 minTokensOut,
        address _referrer
    ) external payable nonReentrant whenNotPaused {
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

        uint256 refund;
        uint256 entryEth = ethInEff;
        if (raisedETH + ethInEff > curveLimit) {
            ethInEff = curveLimit - raisedETH;
        }
        refund = entryEth - ethInEff;
        if (refund > 0) {
            (bool sentRefund, ) = payable(msg.sender).call{value: refund}("");
            require(sentRefund, "ETH refund failed");
            console.log("Refunding excess ETH:", refund);
        }
        // === CURVE CALCULATION ===

        // Current constant product k = vETH * vToken / 1e18
        uint256 currentK = (vETH * vToken) / 1e18;

        // Simulate new vETH after this ETH input
        uint256 newVETH = vETH + ethInEff;

        // Solve for new vToken to maintain k = vETH * vToken
        uint256 newVTOKEN = (currentK * 1e18) / newVETH;

        // Token output = vToken - newVTOKEN
        uint256 tokensToBuy = vToken - newVTOKEN;

        // === SLIPPAGE CHECK ===
        require(tokensToBuy >= minTokensOut, "Slippage too high");

        // === UPDATE VIRTUAL RESERVES ===
        vETH = newVETH;
        vToken = newVTOKEN;
        console.log("this is the curve vToken after buy:.", vToken);
        console.log("tokens to buy:", tokensToBuy);

        // === STATE TRACKING ===
        raisedETH += ethInEff;
        tokensSold += tokensToBuy;
        console.log("raised eth in the curve:", raisedETH);
        console.log("total tokens sold in the curve:", tokensSold);

        // === SEND TOKENS ===
        SafeTransferLib.safeTransfer(token, msg.sender, tokensToBuy);

        // === MIGRATION CHECK === tokensSold >= (vToken + tokensToBuy) ||
        if (raisedETH >= curveLimit) {
            migrationTriggered = true;
            emit MigrationTriggered(raisedETH, tokensSold);

            migrateToLP();
        }

        emit Bought(msg.sender, ethInEff, tokensToBuy);
    }

    // 1.225000000000000000
    // 161,428,295.482767184524959298
    // 10.000000000000000000
    // 8.775000000000000000

    // 972,974,013
    // -------- SELL --------
    /*
    function sell(uint256 tokensToSell, uint256 minEthOut) external nonReentrant whenNotPaused {
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
        console.log("ethbefore and ethafter: ", ethBefore, ethAfter, ethToReturn);
        //require(ethToReturn >= minEthOut, "Slippage too high");
        // 25.975000000000000000 25.874091044924793306

        // ethToReturn = 0.100908955075206694
        // effectiveEth = 0.068618089451140553
        // === EFFECTS ===
        tokensSold = tokensSoldAfter;
        raisedETH -= ethToReturn;

        bool received = CurveToken(token).transferFrom(msg.sender, address(this), tokensToSell);
        require(received, "Token transfer failed");

        // === FEES ===
        uint256 antifudFeeEth = (ethToReturn * factory.antifiludFeeBps()) / 10_000;
        uint256 protoEth = (ethToReturn * factory.protocolFeeBps()) / 10_000;
        uint256 ethInEff = ethToReturn - antifudFeeEth - protoEth;

        uint256 antifudToLauncher = (antifudFeeEth * factory.antifiludLauncherQuotaBps()) / 10_000;
        uint256 antifudToCurve = antifudFeeEth - antifudToLauncher;

        console.log("Effective eth to give user and minEThOut:", ethInEff, minEthOut);

        require(ethInEff >= minEthOut, "Slippage too high");

        bonusLiquidity += antifudToCurve;
        creatorsRewards[creator] += antifudToLauncher;

        payable(msg.sender).transfer(ethInEff);
        emit Sold(msg.sender, ethToReturn, tokensToSell);
    }
*/

    function sell(
        uint256 tokenAmountIn,
        uint256 minEthOut
    ) external nonReentrant whenNotPaused {
        require(token != address(0), "No token address set");
        require(!migrationTriggered, "TradingStopped");
        require(tokenAmountIn > 0, "Zero token amount");
        require(
            IERC20(token).allowance(msg.sender, address(this)) >= tokenAmountIn,
            "Insufficient allowance"
        );

        // Transfer tokens from user to contract
        SafeTransferLib.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            tokenAmountIn
        );

        // === CURVE CALCULATION ===

        uint256 currentK = (vETH * vToken) / 1e18;

        uint256 newVToken = vToken + tokenAmountIn;
        uint256 newVETH = (currentK * 1e18) / newVToken;

        uint256 ethOut = vETH - newVETH;

        // === FEES ===
        uint256 antifudFeeEth = (ethOut * factory.antifiludFeeBps()) / 10_000;
        uint256 protoEth = (ethOut * factory.protocolFeeBps()) / 10_000;
        uint256 ethInEff = ethOut - antifudFeeEth - protoEth;

        uint256 antifudToLauncher = (antifudFeeEth *
            factory.antifiludLauncherQuotaBps()) / 10_000;
        uint256 antifudToCurve = antifudFeeEth - antifudToLauncher;

        console.log(
            "Effective eth to give user and minEThOut:",
            ethInEff,
            minEthOut
        );

        //require(ethInEff >= minEthOut, "Slippage too high");

        bonusLiquidity += antifudToCurve;
        creatorsRewards[creator] += antifudToLauncher;

        require(ethInEff >= minEthOut, "Slippage too high");

        // === TRANSFER ETH OUT ===
        (bool sent, ) = payable(msg.sender).call{value: ethInEff}("");
        require(sent, "ETH transfer failed");

        // === SEND FEES TO TREASURY ===
        (bool sentProto, ) = payable(factory.treasury()).call{value: protoEth}(
            ""
        );
        require(sentProto, "ETH transfer failed");

        // === UPDATE VIRTUAL RESERVES ===
        vToken = newVToken;
        vETH = newVETH;

        console.log(
            "this is the curve ETH balance after sell:",
            address(this).balance
        );
        emit Sold(msg.sender, tokenAmountIn, ethInEff);
    }

    function getTokensOut(
        uint256 ethIn
    ) external view returns (uint256 tokensOut) {
        if (migrationTriggered) revert TradingStopped();
        require(ethIn > 0, "Zero ETH in");

        // calculate the fees
        uint256 refFeeEth = (ethIn * factory.referralFeeBps()) / 10_000;
        uint256 protoEth = (ethIn * factory.protocolFeeBps()) / 10_000;
        uint256 ethInEff = ethIn - refFeeEth - protoEth;

        if (raisedETH + ethInEff > curveLimit) {
            ethInEff = curveLimit - raisedETH;
        }

        // Use the current virtual reserves
        uint256 _vETH = vETH;
        uint256 _vToken = vToken;

        // Recompute the constant product
        uint256 _k = (_vETH * _vToken) / 1e18;

        // Simulate new vETH after ethIn
        uint256 newVETH = _vETH + ethInEff;

        // Solve for new vToken to maintain the product constant
        uint256 newVToken = (_k * 1e18) / newVETH;

        // Output is the difference
        if (_vToken > newVToken) {
            return _vToken - newVToken;
        } else {
            return 0;
        }
    }

    function getMinEthOut(
        uint256 tokenAmountIn
    ) external view returns (uint256 ethOut) {
        require(!migrationTriggered, "TradingStopped");
        require(tokenAmountIn > 0, "Zero token amount");

        uint256 _vETH = vETH;
        uint256 _vToken = vToken;

        uint256 _k = (_vETH * _vToken) / 1e18;

        uint256 newVToken = _vToken + tokenAmountIn;
        uint256 newVETH = (_k * 1e18) / newVToken;

        uint256 grossEthOut = _vETH - newVETH;

        // Fees
        uint256 protoEth = (grossEthOut * factory.protocolFeeBps()) / 10_000;
        uint256 antifudEth = (grossEthOut * factory.antifiludFeeBps()) / 10_000;
        ethOut = grossEthOut - protoEth - antifudEth;

        return ethOut;
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

    // Assumes caller is nonReentrant
    function migrateToLP() internal whenNotPaused {
        require(migrationTriggered, "Migration not triggered yet");
        require(!lpMigrated, "Already migrated");

        // Optional: define flat fees
        uint256 migrationFeesBps = factory.migrationFeeBps();
        uint256 migrationFees = (raisedETH * migrationFeesBps) / 10_000;
        uint256 migrationFeeCreator = (raisedETH *
            factory.migrationFeeBpsCreator()) / 10_000;
        require(
            raisedETH >= migrationFees + migrationFeeCreator,
            "Insufficient ETH to cover fees"
        );

        address migrationFeeWallet = factory.migrationFeeWallet(); // 5% and creator 5%

        uint256 netETH = raisedETH +
            bonusLiquidity -
            migrationFees -
            migrationFeeCreator;

        // === SPOT PRICE ===
        require(vToken > 0, "No virtual tokens left");
        uint256 priceAtMigration = (vETH * 1e18) / vToken;

        // === TOKENS TO PAIR ===
        uint256 tokensToLP = (netETH * 1e18) / priceAtMigration;

        // Ensure we don’t exceed available tokens
        uint256 maxTokensAvailable = CurveToken(token).balanceOf(address(this));
        if (tokensToLP > maxTokensAvailable) {
            tokensToLP = maxTokensAvailable;
        }

        // === Send migration fees ===
        (bool feeSent, ) = payable(migrationFeeWallet).call{
            value: migrationFees
        }("");
        require(feeSent, "Fee transfer failed");

        creatorsRewards[creator] += migrationFeeCreator;

        // === LP Creation ===
        // You can integrate Uniswap, Raydium, etc., here
        // 1. Check if pair exists
        address WBNB = IPancakeRouter02(factory.getPancakeRouter()).WETH(); // WETH address on Ethereum mainnet
        address pair = IPancakeFactory(factory.getPancakeFactory()).getPair(
            token,
            WBNB
        );
        if (pair == address(0)) {
            pair = IPancakeFactory(factory.getPancakeFactory()).createPair(
                token,
                WBNB
            );
        }

        // 2. Approve router to spend your tokens
        IERC20(token).approve(factory.getPancakeRouter(), tokensToLP);

        // 3. Add liquidity (msg.value is your BNB contribution)
        IPancakeRouter02(factory.getPancakeRouter()).addLiquidityETH{
            value: msg.value
        }(
            token,
            tokensToLP,
            (tokensToLP * 95) / 100, // accept up to 5% slippage
            (netETH * 95) / 100,
            address(this), // recipient of LP tokens
            block.timestamp + 300
        );

        /*
        CurveToken(token).approve(address(lpRouter), tokensToLP);
        lpRouter.addLiquidityETH{value: netETH}(
            token,
            tokensToLP,
            0,
            0,
            lpRecipient, // e.g. DAO, creator, etc.
            block.timestamp
        );

        // === FINALIZE ===
        lpMigrated = true;

        */
        emit LPMigrated(tokensToLP, netETH, priceAtMigration);
    }
}
