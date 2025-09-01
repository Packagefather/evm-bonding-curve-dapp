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
    uint96 public referalFeeBps; // 2% charged to referrer
    uint96 public antifiludFeeBps; // 30% charged to filud. 50% goes to creator, 50% goes to liquidity pool
    uint96 public migrationFeeBps; // 10% charged to migration. 50% goes to creator, 50% goes to protocol
    uint96 public antifiludLauncherQuotaBps;
    uint256 public minCurveLimitEth = 10 ether; // min liquidity to add at init
    uint256 public maxCurveLimitEth = 1000 ether; // max liquidity to add at init
    uint256 public fixedAllocationPercent; // % of total supply allocated to bonding curve, e.g., 80% = 80000 bps

    //Token details
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000e18;

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
    event ReferalFeeBpsUpdated(uint96 newFee);
    event AntifiludFeeBpsUpdated(uint96 newFee);
    event MigrationFeeBpsUpdated(uint96 newFee);
    event MinMaxCurveLimitUpdated(uint256 min, uint256 max);

    constructor(ConfigParams memory p) {
        superAdmin = msg.sender;
        curveImpl = p.curveImpl;
        referalFeeBps = p.referalFeeBps;
        antifiludFeeBps = p.antifiludFeeBps;
        migrationFeeBps = p.migrationFeeBps;
        protocolFeeBps = p.protocolFeeBps;
        migrationFeeWallet = p.migrationFeeWallet;
        maxCurveLimitEth = p.maxCurveLimitEth;
        minCurveLimitEth = p.minCurveLimitEth;
        treasury = p.treasury;
        fixedAllocationPercent = p.fixedAllocationPercent;
    }

    struct ConfigParams {
        address curveImpl;
        uint96 protocolFeeBps;
        uint96 referalFeeBps;
        uint96 antifiludFeeBps;
        uint96 migrationFeeBps;
        address treasury;
        address migrationFeeWallet;
        uint256 minCurveLimitEth;
        uint256 maxCurveLimitEth;
        uin256 fixedAllocationPercent;
    }

    struct CreateParams {
        string name;
        string symbol;
        uint256 migrationMcapEth; // FDV at A, e.g., 25e18
        uint256 minHoldingForReferrer;
    }

    function createCurve(
        CreateParams memory p
    ) external returns (address curve, address token) {
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
            p.minHoldingForReferrer
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

    function setReferalFeeBps(uint96 bps) external onlyOwner {
        require(bps <= 10_000, "fee>100%");
        referalFeeBps = bps;
        emit ReferalFeeBpsUpdated(bps);
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

    function setVirtualETH(uint256 _vETH) external onlyOwner {
        require(_vETH > 0, "vETH must be > 0");
        vETH = _vETH;
    }

    function virtualETH() external view returns (uint256) {
        return vETH;
    }
}
