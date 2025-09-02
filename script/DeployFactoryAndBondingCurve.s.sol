// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
//import {HelperConfig} from "./HelperConfig.s.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {CurveFactory} from "../src/Factory.sol";

contract ContractsDeployment is Script {
    function deployFactoryAndBondingCurve()
        public
        returns (CurveFactory, BondingCurve)
    {
        vm.startBroadcast();
        // 1. Deploy BondingCurve implementation
        BondingCurve bondingCurveImpl = new BondingCurve();

        // 2. Build config struct
        CurveFactory.ConfigParams memory config = CurveFactory.ConfigParams({
            curveImpl: address(bondingCurveImpl),
            protocolFeeBps: 200, // example: 2%
            referalFeeBps: 50, // example: 0.5%
            antifiludFeeBps: 10, // example: 0.1%
            migrationFeeBps: 100, // example: 1%
            treasury: address(3), // or your treasury address
            migrationFeeWallet: address(4), // or another wallet
            minCurveLimitEth: 1 ether, // minimum curve limit
            maxCurveLimitEth: 50 ether, // maximum curve limit
            fixedAllocationPercent: 80000 // 80% in basis points
        });

        CurveFactory factory = new CurveFactory(config);

        console.log(
            "BondingCurve Implementation within deployment script:",
            address(bondingCurveImpl)
        );
        console.log("Factory within deployment script:", address(factory));

        vm.stopBroadcast();
        return (factory, bondingCurveImpl);
    }

    function run() external returns (CurveFactory, BondingCurve) {
        return deployFactoryAndBondingCurve();
    }
}
