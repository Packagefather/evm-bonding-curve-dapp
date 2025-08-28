// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ContractsDeployment} from "../../script/DeployFactoryAndBondingCurve.s.sol";
import {LaunchToken} from "../../script/Interactions.s.sol";
import {BondingCurve} from "../../src/BondingCurve.sol";
import {CurveFactory} from "../../src/Factory.sol";
//import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test} from "forge-std/Test.sol";
import {Script, console} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

//import {ZkSyncChainChecker} from "lib/foundry-devops/src/ZkSyncChainChecker.sol";

contract InteractionsTest is StdCheats, Test {
    BondingCurve public bondingCurve;
    CurveFactory public curveFactory;

    //uint256 public constant SEND_VALUE = 0.1 ether; // just a value to make sure we are sending enough!
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant GAS_PRICE = 1;

    address public constant USER = address(1);

    //console.log("USER address:", USER);

    // uint256 public constant SEND_VALUE = 1e18;
    // uint256 public constant SEND_VALUE = 1_000_000_000_000_000_000;
    // uint256 public constant SEND_VALUE = 1000000000000000000;

    function setUp() external {
        //skipZkSync
        // if (!isZkSyncChain()) {
        //     DeployFundMe deployer = new DeployFundMe();
        //     (fundMe, helperConfig) = deployer.deployFundMe();
        // } else {
        //     helperConfig = new HelperConfig();
        //     fundMe = new FundMe(
        //         helperConfig.getConfigByChainId(block.chainid).priceFeed
        //     );
        // }
        //You're doing the same kind of deployment (forge script script/DeployBondingCurve.s.sol --broadcast -vvvv),
        //but to Foundry's isolated test VM
        console.log("USER ADDRESS within integration test", USER);
        ContractsDeployment deployer = new ContractsDeployment();
        (curveFactory, bondingCurve) = deployer.deployFactoryAndBondingCurve();
        console.log("Factory", address(curveFactory));
        console.log("Curve", address(bondingCurve));

        vm.deal(USER, STARTING_USER_BALANCE);
    }

    function testUserCanCreateCurveFromFactory() public {
        uint256 preUserBalance = address(USER).balance;
        //uint256 preOwnerBalance = address(bondingCurve.getOwner()).balance;
        //uint256 originalFundMeBalance = address(bondingCurve).balance;

        // Using vm.prank to simulate funding from the USER address
        vm.prank(USER);
        //curveFactory.createCurve();

        // this is us calling via the interaction script
        // we can call it directly since we have the factory instance within this test environment
        // like this  curveFactory.createcurve();

        // run() is your script’s "main" entry point — it only runs when you execute the script with forge script.
        //Tests don’t run run(), they call functions directly as written in your test code.
        LaunchToken launchToken = new LaunchToken();
        (address curve, address token) = launchToken.initializeCurve(
            address(curveFactory)
        ); // this is telling it which contract interface to use and the function to call

        console.log("Curve and Token", curve, token);
        BondingCurve newCurve = BondingCurve(payable(address(curve)));
        //uint256 afterUserBalance = address(USER).balance;
        //uint256 afterOwnerBalance = address(bondingCurve.getOwner()).balance;

        uint256 curve_limit = newCurve.curveLimit();
        console.log("Curve Limit", curve_limit);
        assertEq(curve_limit, 10 ether);
        // assertEq(afterUserBalance + SEND_VALUE, preUserBalance);
        // assertEq(
        //     preOwnerBalance + SEND_VALUE + originalFundMeBalance,
        //     afterOwnerBalance
        // );
    }
}
