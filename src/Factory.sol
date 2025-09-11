// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin-contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {BondingCurve} from "./BondingCurve.sol";
import {CurveToken} from "./CurveToken.sol";

contract CurveFactory is Ownable(msg.sender) {
    //_checkOwneraddress public immutable CURVE_IMPL;
    address public superAdmin; // protocol owner, can change treasury
    address public curveImpl;
    address public treasury; // where protocol fees go
    address public migrationFeeWallet; // where migration fees go

    uint96 public protocolFeeBps; // 2% - protocol cut on both buy and sell
    uint96 public referralFeeBps; // 2% charged to referrer
    uint96 public antifiludFeeBps; // 30% charged to filud. 50% goes to creator, 50% goes to liquidity pool
    uint96 public migrationFeeBps; // 10% charged to migration. 50% goes to creator, 50% goes to protocol
    uint96 public migrationFeeBpsCreator;
    uint96 public antifiludLauncherQuotaBps;
    uint256 public minCurveLimitEth = 0.1 ether; // min liquidity to add at init
    uint256 public maxCurveLimitEth = 1000 ether; // max liquidity to add at init
    uint256 public fixedAllocationPercent; // % of total supply allocated to bonding curve, e.g., 80% = 80000 bps
    uint256 public fixedAllocationOfVToken; // % of vToken to sell, e.g., 99.99% = 9999 bps
    //Token details
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000e18;

    address public PancakeRouter;
    address public PancakeFactory;

    // Pool details
    //uint256 public vETH = 2.5e18; // initial virtual ETH, e.g., 2.5e18 wei (2.5 ETH)

    mapping(address => bool) public tokenUsed;

    event ImplementationUpdated(address indexed newImpl);
    event CurveCreated(
        address indexed curve,
        address indexed token,
        address indexed creator,
        uint256 totalSupply,
        uint256 migrationMcapEth
    );
    event TreasuryUpdated(address indexed newTreasury);
    event superAdminUpdated(address indexed superAdmin);
    event MigrationFeeWalletUpdated(address indexed newTreasury);
    event ProtocolFeeUpdated(uint96 newFee);
    event ReferralFeeBpsUpdated(uint96 newFee);
    event AntifiludFeeBpsUpdated(uint96 newFee);
    event MigrationFeeBpsUpdated(uint96 newFee);
    event MinMaxCurveLimitUpdated(uint256 min, uint256 max);
    event MigrationFeeBpsCreatorUpdated(uint96 _basisPoint);

    struct ConfigParams {
        address curveImpl;
        uint96 protocolFeeBps;
        uint96 referralFeeBps;
        uint96 antifiludFeeBps;
        uint96 migrationFeeBps; // 5%
        uint96 migrationFeeBpsCreator; // 5%
        address treasury;
        address migrationFeeWallet;
        uint256 minCurveLimitEth;
        uint256 maxCurveLimitEth;
        uint256 fixedAllocationPercent;
        uint256 fixedAllocationOfVTokenPercent;
        uint96 antifiludLauncherQuotaBps;
    }

    struct CreateParams {
        string name;
        string symbol;
        uint256 migrationMcapEth; // FDV at A, e.g., 25e18
        uint256 minHoldingForReferrer;
        uint256 vETH;
    }

    constructor(ConfigParams memory p) {
        require(p.curveImpl != address(0), "Invalid implementation");
        require(p.treasury != address(0), "Invalid treasury");
        require(p.migrationFeeWallet != address(0), "Invalid wallet");
        require(p.protocolFeeBps <= 10_000, "fee>100%");
        require(p.referralFeeBps <= 10_000, "fee>100%");
        require(p.antifiludFeeBps <= 10_000, "fee>100%");
        require(p.migrationFeeBps <= 10_000, "fee>100%");
        require(p.migrationFeeBpsCreator <= 10_000, "fee>100%");
        require(p.minCurveLimitEth < p.maxCurveLimitEth, "min>=max");
        require(p.fixedAllocationPercent <= 10_000, "percent>100%");
        require(p.fixedAllocationOfVTokenPercent <= 10_000, "percent>100%");
        require(p.antifiludLauncherQuotaBps <= 10_000, "percent>100%");

        superAdmin = msg.sender;
        curveImpl = p.curveImpl;
        referralFeeBps = p.referralFeeBps;
        antifiludFeeBps = p.antifiludFeeBps;
        migrationFeeBps = p.migrationFeeBps;
        migrationFeeBpsCreator = p.migrationFeeBpsCreator;
        protocolFeeBps = p.protocolFeeBps;
        migrationFeeWallet = p.migrationFeeWallet;
        maxCurveLimitEth = p.maxCurveLimitEth;
        minCurveLimitEth = p.minCurveLimitEth;
        treasury = p.treasury;
        fixedAllocationPercent = p.fixedAllocationPercent;
        fixedAllocationOfVToken = p.fixedAllocationOfVTokenPercent;
        antifiludLauncherQuotaBps = p.antifiludLauncherQuotaBps;
    }

    function createCurve(
        CreateParams memory p
    ) external returns (address curve, address token) {
        require(PancakeFactory != address(0), "PancakeFactory not set");
        require(PancakeRouter != address(0), "PancakeRouter not set");

        // 1) Deploy token
        token = address(
            new CurveToken(p.name, p.symbol, decimals, address(this))
        );

        // Mark token as used BEFORE initializing the clone
        require(!tokenUsed[token], "Token already used");

        // 2) Clone curve & init
        curve = Clones.clone(curveImpl);
        BondingCurve(payable(curve)).initialize(
            token,
            p.migrationMcapEth,
            msg.sender, // this is the creator
            p.minHoldingForReferrer,
            p.vETH
        );

        tokenUsed[token] = true;
        // Mint full allocation to the bonding curve
        CurveToken(token).mint(curve, totalSupply);

        // Renounce ownership so no one can mint more tokens
        CurveToken(token).renounceOwnership();

        emit CurveCreated(
            curve,
            token,
            msg.sender,
            totalSupply,
            p.migrationMcapEth
        );
    }

    // --- ADMIN ---
    function setProtocolFeeBps(uint96 bps) external onlyOwner {
        require(bps <= 10_000, "fee>100%");
        protocolFeeBps = bps;
        emit ProtocolFeeUpdated(bps);
    }

    function setReferralFeeBps(uint96 bps) external onlyOwner {
        require(bps <= 10_000, "fee>100%");
        referralFeeBps = bps;
        emit ReferralFeeBpsUpdated(bps);
    }

    function setAntifiludFeeBps(uint96 bps) external onlyOwner {
        require(bps <= 10_000, "fee>100%");
        antifiludFeeBps = bps;
        emit AntifiludFeeBpsUpdated(bps);
    }

    function setMigrationFeeBps(uint96 bps) external onlyOwner {
        require(bps <= 10_000, "fee>100%");
        migrationFeeBps = bps;
        emit MigrationFeeBpsUpdated(bps);
    }

    function setMinMaxCurveLimitEth(
        uint256 _min,
        uint256 _max
    ) external onlyOwner {
        require(_min < _max, "min>=max");
        minCurveLimitEth = _min;
        maxCurveLimitEth = _max;
        emit MinMaxCurveLimitUpdated(_min, _max);
    }

    // setting the wallet to receive the migration fees
    function setMigrationFeeWallet(address _wallet) external onlyOwner {
        migrationFeeWallet = _wallet;
        emit MigrationFeeWalletUpdated(_wallet);
    }

    function setMigrationFeeBpsCreator(uint96 _basisPoint) external onlyOwner {
        migrationFeeBpsCreator = _basisPoint;
        emit MigrationFeeBpsCreatorUpdated(_basisPoint);
    }

    // Upgrade the implementation for future clones
    function setImplementation(address newImpl) external onlyOwner {
        require(newImpl != address(0), "Invalid implementation");
        curveImpl = newImpl;
        emit ImplementationUpdated(newImpl);
    }

    // settingt he wallet to receive the fees
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    function setSuperAdmin(address _superAdmin) external onlyOwner {
        superAdmin = _superAdmin;
        emit superAdminUpdated(_superAdmin);
    }

    function setAntifiludLauncherQuotaBps(uint96 _bps) external onlyOwner {
        require(_bps <= 10_000, "fee>100%");
        antifiludLauncherQuotaBps = _bps;

        //emit setting
    }

    function setPancakeRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid address");
        PancakeRouter = _router;
    }

    function setPancakeFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid address");
        PancakeFactory = _factory;
    }
}
