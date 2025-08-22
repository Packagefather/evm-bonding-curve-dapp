// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {BondingCurve} from "../src/BondingCurve.sol";

contract DeployBondingCurve is Script {
    function deployBondingCurve() public returns (BondingCurve, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!
        address priceFeed = helperConfig
            .getConfigByChainId(block.chainid)
            .priceFeed;

        vm.startBroadcast();
        BondingCurve bondingCurve = new BondingCurve(priceFeed);
        vm.stopBroadcast();
        return (bondingCurve, helperConfig);
    }

    function run() external returns (BondingCurve, HelperConfig) {
        return deployBondingCurve();
    }
}
