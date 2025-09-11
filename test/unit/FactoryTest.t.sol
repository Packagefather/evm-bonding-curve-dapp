// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ContractsDeployment} from "../../script/DeployFactoryAndBondingCurve.s.sol";
import "../../src/BondingCurve.sol";
import "../../src/CurveToken.sol";
import "../../src/Factory.sol";
import "../constants/constants.sol";

contract CurveFactoryTest is Test {
    using Constants for *;
    CurveFactory public curveFactory;

    CurveToken public token;
    BondingCurve public bondingCurve;
    BondingCurve public bondingCurveImpl;

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
    address public ADMINISTRATOR = makeAddr("Admin");
    address Alice = makeAddr("Alice");

    function setUp() public {
        vm.deal(ADMINISTRATOR, STARTING_USER_BALANCE);
        //vm.prank(ADMINISTRATOR); // for single calls with startprank is for all calls after it
        vm.startPrank(ADMINISTRATOR);
        // 1. Deploy BondingCurve implementation
        bondingCurveImpl = new BondingCurve();
        // 2. Build config struct
        CurveFactory.ConfigParams memory config = CurveFactory.ConfigParams({
            curveImpl: address(bondingCurveImpl),
            protocolFeeBps: 200, // example: 2%
            referralFeeBps: 50, // example: 0.5%
            antifiludFeeBps: 10, // example: 0.1%
            migrationFeeBps: 500, // example: 5%
            migrationFeeBpsCreator: 500, // 5%
            treasury: address(3), // or your treasury address
            migrationFeeWallet: address(4), // or another wallet
            minCurveLimitEth: 1 ether, // minimum curve limit
            maxCurveLimitEth: 50 ether, // maximum curve limit
            fixedAllocationPercent: 8000, // 80% in basis points
            fixedAllocationOfVTokenPercent: 9999, // 99.99% in basis points of vToken to sell
            antifiludLauncherQuotaBps: 5000
        });

        // ContractsDeployment deployer = new ContractsDeployment();
        // (curveFactory, bondingCurveImpl) = deployer
        //     .deployFactoryAndBondingCurve();

        // We are deploying directly here instead of importing from script so we can set our ADMINISTRATOR as owner
        curveFactory = new CurveFactory(config);

        console.log("Factory", address(curveFactory));
        console.log("Curve Implementation Contract", address(bondingCurveImpl));

        CurveFactory.CreateParams memory params = CurveFactory.CreateParams({
            name: "MyToken",
            symbol: "MTK",
            migrationMcapEth: Constants.CURVE_LIMIT, // 25 ETH as full FDV
            minHoldingForReferrer: 1000e18, // Minimum holding to refer (1 token)
            vETH: Constants.CURVE_VETH
        });

        (address bondingCurveAddr, address tokenAddr) = CurveFactory(
            (address(curveFactory))
        ).createCurve(params);
        bondingCurve = BondingCurve(payable(bondingCurveAddr));
        token = CurveToken(tokenAddr);

        console.log("Deployed Clone Curve at:", address(bondingCurve));
        console.log("Deployed Token at:", address(token));

        address owner = curveFactory.owner();
        console.log("Owner of CurveFactory:", owner);
        vm.stopPrank(); // Optional, but tidy
    }

    function testInitialValues() public view {
        assertEq(curveFactory.owner(), ADMINISTRATOR, "superAdmin mismatch");
        assertEq(
            curveFactory.curveImpl(),
            address(bondingCurveImpl),
            "curveImpl mismatch"
        );
        assertEq(curveFactory.protocolFeeBps(), 200, "protocolFeeBps mismatch");
        assertEq(curveFactory.referralFeeBps(), 50, "referalFeeBps mismatch");
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

    function nonAdminCannotSetProtocolFee() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setProtocolFeeBps(300);
    }

    function adminCanSetProtocolFee() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setProtocolFeeBps(300);
        assertEq(curveFactory.protocolFeeBps(), 300, "protocolFeeBps mismatch");
    }

    function nonAdminCannotSetReferalFee() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setReferralFeeBps(60);
    }

    function adminCanSetReferalFee() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setReferralFeeBps(60);
        assertEq(curveFactory.referralFeeBps(), 60, "referalFeeBps mismatch");
    }

    function nonAdminCannotSetAntifiludFee() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setAntifiludFeeBps(20);
    }

    function adminCanSetAntifiludFee() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setAntifiludFeeBps(20);
        assertEq(
            curveFactory.antifiludFeeBps(),
            20,
            "antifiludFeeBps mismatch"
        );
    }

    function nonAdminCannotSetMigrationFee() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setMigrationFeeBps(150);
    }

    function adminCanSetMigrationFee() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setMigrationFeeBps(150);
        assertEq(
            curveFactory.migrationFeeBps(),
            150,
            "migrationFeeBps mismatch"
        );
    }

    function setAntifiludLauncherQuotaBps() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setAntifiludLauncherQuotaBps(500);
        assertEq(
            curveFactory.antifiludLauncherQuotaBps(),
            500,
            "antifiludLauncherQuotaBps mismatch"
        );
    }

    function nonAdminCannotSetAntifiludLauncherQuotaBps() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setAntifiludLauncherQuotaBps(500);
    }

    function nonAdminCannotSetMinMaxCurveLimitEth() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setMinMaxCurveLimitEth(2 ether, 40 ether);
    }

    function adminCanSetMinMaxCurveLimitEth() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setMinMaxCurveLimitEth(2 ether, 40 ether);
        assertEq(
            curveFactory.minCurveLimitEth(),
            2 ether,
            "minCurveLimitEth mismatch"
        );
        assertEq(
            curveFactory.maxCurveLimitEth(),
            40 ether,
            "maxCurveLimitEth mismatch"
        );
    }

    function nonAdminCannotSetMigrationFeeWallet() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setMigrationFeeWallet(address(5));
    }

    function adminCanSetMigrationFeeWallet() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setMigrationFeeWallet(address(5));
        assertEq(
            curveFactory.migrationFeeWallet(),
            address(5),
            "migrationFeeWallet mismatch"
        );
    }

    function nonAdminCannotSetTreasury() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setTreasury(address(6));
    }

    function adminCanSetTreasury() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setTreasury(address(6));
        assertEq(curveFactory.treasury(), address(6), "treasury mismatch");
    }

    function nonAdminCannotSetImplementation() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setImplementation(address(0xDEAD));
    }

    function adminCanSetImplementation() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setImplementation(address(0xDEAD));
        assertEq(
            curveFactory.curveImpl(),
            address(0xDEAD),
            "curveImpl mismatch"
        );
    }

    function nonAdminCannotSetSuperAdmin() public {
        vm.prank(USER);
        vm.expectRevert("Ownable: caller is not the owner");
        curveFactory.setSuperAdmin(address(7));
    }

    function adminCanSetSuperAdmin() public {
        vm.prank(ADMINISTRATOR);
        curveFactory.setSuperAdmin(address(7));
        assertEq(curveFactory.superAdmin(), address(7), "superAdmin mismatch");
    }

    function testCannotSetFeesAbove100Percent() public {
        vm.prank(ADMINISTRATOR);
        vm.expectRevert("fee>100%");
        curveFactory.setProtocolFeeBps(10_001);

        vm.prank(ADMINISTRATOR);
        vm.expectRevert("fee>100%");
        curveFactory.setReferralFeeBps(10_001);

        vm.prank(ADMINISTRATOR);
        vm.expectRevert("fee>100%");
        curveFactory.setAntifiludFeeBps(10_001);

        vm.prank(ADMINISTRATOR);
        vm.expectRevert("fee>100%");
        curveFactory.setMigrationFeeBps(10_001);
    }

    function testCannotSetMinGreaterThanMaxCurveLimitEth() public {
        vm.prank(ADMINISTRATOR);
        vm.expectRevert("min>=max");
        curveFactory.setMinMaxCurveLimitEth(10 ether, 5 ether);
    }

    function testCannotSetInvalidImplementation() public {
        vm.prank(ADMINISTRATOR);
        vm.expectRevert("Invalid implementation");
        curveFactory.setImplementation(address(0));
    }

    function testCreateCurve() public {
        CurveFactory.CreateParams memory params = CurveFactory.CreateParams({
            name: "AnotherToken",
            symbol: "ATK",
            migrationMcapEth: 5 ether, // 25 ETH as full FDV
            minHoldingForReferrer: 500e18, // Minimum holding to refer (0.5 token)
            vETH: Constants.CURVE_VETH
        });
        vm.prank(USER);
        (address bondingCurveAddr, address tokenAddr) = CurveFactory(
            (address(curveFactory))
        ).createCurve(params);
        BondingCurve newBondingCurve = BondingCurve(payable(bondingCurveAddr));
        CurveToken newToken = CurveToken(tokenAddr);
        console.log(
            "Deployed Second Clone Curve at:",
            address(newBondingCurve)
        );
        console.log("Deployed New Token at:", address(newToken));
    }
}
