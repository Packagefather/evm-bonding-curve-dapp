// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin-contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {BondingCurve} from "./BondingCurve.sol";
import {CurveToken} from "./CurveToken.sol";

contract CurveFactory is Ownable(msg.sender) {
    //_checkOwneraddress public immutable CURVE_IMPL;
    address public curveImpl;
    address public treasury; // where protocol fees go
    uint96 public protocolFeeBps; // e.g., 200 = 2%

    event ImplementationUpdated(address indexed newImpl);
    event CurveCreated(
        address indexed curve,
        address indexed token,
        address indexed creator,
        uint256 iVToken,
        uint256 iVEth,
        uint256 allocationA, // ~80% of supply
        uint256 migrationMcapEth, // e.g. 25 ETH FDV at A
        uint96 tradeFeeBps
    );

    constructor(address _curveImpl, address _treasury, uint96 _protocolFeeBps) {
        curveImpl = _curveImpl;
        treasury = _treasury;
        protocolFeeBps = _protocolFeeBps;
    }

    function setTreasury(address t) external onlyOwner {
        treasury = t;
    }

    function setProtocolFeeBps(uint96 bps) external onlyOwner {
        require(bps <= 10_000, "fee>100%");
        protocolFeeBps = bps;
    }

    // Upgrade the implementation for future clones
    function setImplementation(address newImpl) external onlyOwner {
        require(newImpl != address(0), "Invalid implementation");
        curveImpl = newImpl;
        emit ImplementationUpdated(newImpl);
    }

    struct CreateParams {
        string name;
        string symbol;
        uint8 decimals; // usually 18
        uint256 totalSupply; // e.g., 1e9 * 1e18
        uint256 iVToken; // 1.06e27 minimal units
        uint256 iVEth; // 1.6e18 wei
        uint256 allocationA; // 80% of totalSupply
        uint256 migrationMcapEth; // FDV at A, e.g., 25e18
        uint96 tradeFeeBps; // curve trade fee
        address creator;
    }

    function createCurve(
        CreateParams memory p
    ) external returns (address curve, address token) {
        // 1) Deploy token
        token = address(
            new CurveToken(p.name, p.symbol, p.decimals, address(this))
        );

        // 2) Clone curve & init
        curve = Clones.clone(curveImpl);
        BondingCurve(payable(curve)).initialize(
            token,
            p.iVToken,
            p.iVEth,
            p.allocationA,
            p.migrationMcapEth,
            p.tradeFeeBps,
            treasury,
            protocolFeeBps,
            p.creator
        );

        // 3) Hand minting rights to curve; mint initial supply to curve if needed
        CurveToken(token).transferOwnership(curve); // curve controls minting

        emit CurveCreated(
            curve,
            token,
            p.creator,
            p.iVToken,
            p.iVEth,
            p.allocationA,
            p.migrationMcapEth,
            p.tradeFeeBps
        );
    }
}
