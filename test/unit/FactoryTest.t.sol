// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ContractsDeployment} from "../../script/DeployFactoryAndBondingCurve.s.sol";
import "../../src/BondingCurve.sol";
import "../../src/CurveToken.sol";
import "../../src/Factory.sol";

contract CurveFactoryTest is Test {
    CurveFactory public curveFactory;
    BondingCurve bondingCurveImpl = new BondingCurve();
    CurveToken public token;
    BondingCurve public bondingCurve;

    address curveImpl = address(0xBEEF);
    //address curveImpl2;
    address public user = address(1);
    address public referrer = address(2);
    address public treasury = address(3);
    address public migrationFeeWallet = address(4);

    uint256 public totalSupply = 1_000_000_000 ether;
    uint256 public curveLimit = 20 ether;
    uint256 public allocation = 80000; // 80%
    uint256 public minHold = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant GAS_PRICE = 1;

    address public constant USER = address(1);
    address public constant ADMINISTRATOR = address(99);

    function setUp() public {
        ContractsDeployment deployer = new ContractsDeployment();
        (curveFactory, bondingCurveImpl) = deployer
            .deployFactoryAndBondingCurve();
        console.log("Factory", address(curveFactory));
        console.log("Curve Implementation Contract", address(bondingCurveImpl));

        vm.deal(ADMINISTRATOR, STARTING_USER_BALANCE);

        CurveFactory.CreateParams memory params = CurveFactory.CreateParams({
            name: "MyToken",
            symbol: "MTK",
            migrationMcapEth: 10 ether, // 25 ETH as full FDV
            minHoldingForReferrer: 1000e18 // Minimum holding to refer (1 token)
        });

        vm.prank(ADMINISTRATOR);
        (address bondingCurveAddr, address tokenAddr) = CurveFactory(
            (address(curveFactory))
        ).createCurve(params);
        bondingCurve = BondingCurve(payable(bondingCurveAddr));
        token = CurveToken(tokenAddr);

        console.log("Deployed Clone Curve at:", address(bondingCurve));
        console.log("Deployed Token at:", address(token));
    }

    function testInitialValues() public view {
        assertEq(
            curveFactory.curveImpl(),
            address(bondingCurveImpl),
            "curveImpl mismatch"
        );
        assertEq(curveFactory.protocolFeeBps(), 200, "protocolFeeBps mismatch");
        assertEq(curveFactory.referalFeeBps(), 50, "referalFeeBps mismatch");
        assertEq(
            curveFactory.antifiludFeeBps(),
            10,
            "antifiludFeeBps mismatch"
        );
        assertEq(
            curveFactory.migrationFeeBps(),
            100,
            "migrationFeeBps mismatch"
        );
        assertEq(curveFactory.treasury(), treasury, "treasury mismatch");
        assertEq(
            curveFactory.migrationFeeWallet(),
            migrationFeeWallet,
            "migrationFeeWallet mismatch"
        );
        assertEq(
            curveFactory.minCurveLimitEth(),
            1 ether,
            "minCurveLimitEth mismatch"
        );
        assertEq(
            curveFactory.maxCurveLimitEth(),
            50 ether,
            "maxCurveLimitEth mismatch"
        );
        assertEq(
            curveFactory.fixedAllocationPercent(),
            80000,
            "fixedAllocationPercent mismatch"
        );
        assertEq(
            curveFactory.totalSupply(),
            1_000_000_000e18,
            "totalSupply mismatch"
        );
        assertEq(curveFactory.decimals(), 18, "decimals mismatch");

        // call the set super admin function then do this test
        // assertEq(
        //     curveFactory.superAdmin(),
        //     address(this),
        //     "superAdmin mismatch"
        // );
    }
}
