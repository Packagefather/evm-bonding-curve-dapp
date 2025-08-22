// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployBondingCurve} from "../script/DeployBondingCurve.s.sol";
import {BondingCurve} from "../src/BondingCurve.sol";
import {HelperConfig, CodeConstants} from "../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract BondingCurveTest is Test {
    BondingCurve public bondingCurve;
    HelperConfig public helperConfig;

    uint256 public constant SEND_VALUE = 0.1 ether; // just a value to make sure we are sending enough!
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant GAS_PRICE = 1;

    uint160 public constant USER_NUMBER = 50;
    address public constant USER = address(USER_NUMBER); //USER = an Ethereum address derived from that number.

    // uint256 public constant SEND_VALUE = 1e18;
    // uint256 public constant SEND_VALUE = 1_000_000_000_000_000_000;
    // uint256 public constant SEND_VALUE = 1000000000000000000;

    address Alice = makeAddr("Alice");
    address Bob = makeAddr("Bob");
    address Charlie = makeAddr("Charlie");

    function setUp() external {
        DeployBondingCurve deployer = new DeployBondingCurve();
        (bondingCurve, helperConfig) = deployer.deployBondingCurve();

        console.log("I want to see who this user is", USER);
        vm.deal(USER, 1 ether);
        vm.deal(address(3), 1 ether);
        //emit log_address(USER);
        // this is the first one that runs
        // if (!isZkSyncChain()) {
        //     DeployFundMe deployer = new DeployFundMe();
        //     (fundMe, helperConfig) = deployer.deployFundMe();
        // } else {
        //     MockV3Aggregator mockPriceFeed = new MockV3Aggregator(
        //         DECIMALS,
        //         INITIAL_PRICE
        //     );
        //     fundMe = new FundMe(address(mockPriceFeed));
        // }
        // vm.deal(USER, STARTING_USER_BALANCE);
    }

    function testPriceFeedSetCorrectly() public {
        // address retreivedPriceFeed = address(fundMe.getPriceFeed());
        // // (address expectedPriceFeed) = helperConfig.activeNetworkConfig();
        // address expectedPriceFeed = helperConfig
        //     .getConfigByChainId(block.chainid)
        //     .priceFeed;
        // assertEq(retreivedPriceFeed, expectedPriceFeed);
    }

    /*
    function testFundFailsWithoutEnoughETH() public skipZkSync {
        vm.expectRevert();
        fundMe.fund();
    }
*/
    function testFundUpdatesFundedDataStructure() public {
        vm.startPrank(USER);

        bondingCurve.fund{value: SEND_VALUE}();
        vm.stopPrank();

        uint256 amountFunded = bondingCurve.getAddressToAmountFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    function testAddsFunderToArrayOfFunders() public {
        vm.startPrank(USER);
        bondingCurve.fund{value: SEND_VALUE}();
        vm.stopPrank();

        address funder = bondingCurve.getFunder(0);
        assertEq(funder, USER);
    }

    // https://twitter.com/PaulRBerg/status/1624763320539525121

    modifier funded() {
        vm.prank(USER);
        bondingCurve.fund{value: SEND_VALUE}();
        assert(address(bondingCurve).balance > 0);
        _;
    }

    function testOnlyOwnerCanWithdraw() public funded {
        vm.expectRevert();
        vm.prank(address(3)); // Not the owner
        bondingCurve.withdraw();
    }

    function testWithdrawFromASingleFunder() public funded {
        // Arrange
        uint256 startingFundMeBalance = address(bondingCurve).balance;
        uint256 startingOwnerBalance = bondingCurve.getOwner().balance;

        // Anvil local chain has a defaulted gas price of 0 wei
        // so, to emulate real chain behavior, we set a gas price
        vm.txGasPrice(GAS_PRICE);
        // uint256 gasStart = gasleft(); eg 1000. At this point, we have 1000 gas left. meaning, nothing used yet
        // // Act
        vm.startPrank(bondingCurve.getOwner());
        bondingCurve.withdraw(); // this maybe used 200 gas
        vm.stopPrank();

        // uint256 gasEnd = gasleft();  // 800 gas left, meaning we used 200 gas
        // uint256 gasUsed = (gasStart - gasEnd) * tx.gasprice;

        // Assert
        uint256 endingFundMeBalance = address(bondingCurve).balance;
        uint256 endingOwnerBalance = bondingCurve.getOwner().balance;
        assertEq(endingFundMeBalance, 0);
        assertEq(
            startingFundMeBalance + startingOwnerBalance,
            endingOwnerBalance // + gasUsed
        );
    }

    // Can we do our withdraw function a cheaper way?
    function testWithdrawFromMultipleFunders() public funded {
        uint160 numberOfFunders = 10;
        uint160 startingFunderIndex = 2 + USER_NUMBER;

        uint256 originalFundMeBalance = address(bondingCurve).balance; // This is for people running forked tests!

        for (
            uint160 i = startingFunderIndex;
            i < numberOfFunders + startingFunderIndex;
            i++
        ) {
            // we get hoax from stdcheats
            // prank + deal
            hoax(address(i), STARTING_USER_BALANCE);
            bondingCurve.fund{value: SEND_VALUE}();
        }

        uint256 startingFundedeBalance = address(bondingCurve).balance;
        uint256 startingOwnerBalance = bondingCurve.getOwner().balance;

        vm.startPrank(bondingCurve.getOwner());
        bondingCurve.withdraw();
        vm.stopPrank();

        assert(address(bondingCurve).balance == 0);
        assert(
            startingFundedeBalance + startingOwnerBalance ==
                bondingCurve.getOwner().balance
        );

        uint256 expectedTotalValueWithdrawn = ((numberOfFunders) * SEND_VALUE) +
            originalFundMeBalance;
        uint256 totalValueWithdrawn = bondingCurve.getOwner().balance -
            startingOwnerBalance;

        assert(expectedTotalValueWithdrawn == totalValueWithdrawn);
    }
}
