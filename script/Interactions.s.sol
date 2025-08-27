// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {CurveFactory} from "../src/Factory.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract LaunchToken is Script {
    uint256 SEND_VALUE = 0.1 ether;
    CurveFactory.CreateParams params =
        CurveFactory.CreateParams({
            name: "MyToken",
            symbol: "MTK",
            allocationPercent: 80000, // 80% in basis points (e.g., 80000 = 80%)
            migrationMcapEth: 25 ether, // 25 ETH as full FDV
            minHoldingForReferrer: 1e18 // Minimum holding to refer (1 token)
        });

    function initializeCurve(address mostRecentlyDeployed) public {
        vm.startBroadcast();
        CurveFactory((mostRecentlyDeployed)).createCurve(params);
        vm.stopBroadcast();
        console.log("Funded FundMe with %s", SEND_VALUE);
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "CurveFactory",
            block.chainid
        );
        initializeCurve(mostRecentlyDeployed);
    }
}

/*
contract WithdrawFundMe is Script {
    function withdrawFundMe(address mostRecentlyDeployed) public {
        vm.startBroadcast();
        BondingCurve(payable(mostRecentlyDeployed)).withdraw();
        vm.stopBroadcast();
        console.log("Withdraw FundMe balance!");
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "BondingCurve",
            block.chainid
        );
        withdrawFundMe(mostRecentlyDeployed);
    }
}
*/
