// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/Test.sol";
//import {HelperConfig} from "./HelperConfig.s.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {CurveFactory} from "../src/Factory.sol";

contract ContractsDeployment is Script {
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public ADMINISTRATOR = makeAddr("Admin");
    address Treasury = makeAddr("Treasury");

    function deployFactoryAndBondingCurve()
        public
        returns (CurveFactory, BondingCurve)
    {
        //vm.startBroadcast(); // - we can add this in the test file for mainnet deployment.
        // since we are using this deployment script for test, too, we will remove it from here, since test cannot use broadcast
        // as foundry does not allow test to user broadcast and prank together.
        // 1. Deploy BondingCurve implementation
        vm.deal(ADMINISTRATOR, STARTING_USER_BALANCE);
        vm.startPrank(ADMINISTRATOR);
        BondingCurve bondingCurveImpl = new BondingCurve();

        // 2. Build config struct
        CurveFactory.ConfigParams memory config = CurveFactory.ConfigParams({
            curveImpl: address(bondingCurveImpl),
            protocolFeeBps: 200, // example: 2%
            referralFeeBps: 50, // example: 0.5%
            antifiludFeeBps: 10, // example: 0.1%
            migrationFeeBps: 100, // example: 1%
            treasury: Treasury, // or your treasury address
            migrationFeeWallet: address(4), // or another wallet
            minCurveLimitEth: 1 ether, // minimum curve limit
            maxCurveLimitEth: 50 ether, // maximum curve limit
            fixedAllocationPercent: 80000 // 80% in basis points
        });

        CurveFactory factory = new CurveFactory(config);

        // console.log(
        //     "BondingCurve Implementation within deployment script:",
        //     address(bondingCurveImpl)
        // );
        //console.log("Factory within deployment script:", address(factory));
        //console.log("address(this):", address(this));
        //console.log("ADMINISTRATOR:", ADMINISTRATOR);
        //console.log("Owner of Factory:", factory.owner());
        //vm.stopBroadcast();
        vm.stopPrank();
        return (factory, bondingCurveImpl);
    }

    function run() external returns (CurveFactory, BondingCurve) {
        return deployFactoryAndBondingCurve();
    }
}
