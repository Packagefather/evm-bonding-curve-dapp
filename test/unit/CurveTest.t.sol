// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ContractsDeployment} from "../../script/DeployFactoryAndBondingCurve.s.sol";
import {BondingCurve} from "../../src/BondingCurve.sol";
import {CurveFactory} from "../../src/Factory.sol";
import {CurveToken} from "../../src/CurveToken.sol";
//import {HelperConfig, CodeConstants} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import "../helpers/CurveMath.sol";
import "../constants/constants.sol";

contract BondingCurveTest is Test {
    using Constants for *;
    BondingCurve public bondingCurve;
    BondingCurve public bondingCurveImpl;
    CurveFactory public factory;
    CurveToken public token;
    CurveMath public math;

    uint256 public constant SEND_VALUE = 2 ether; // just a value to make sure we are sending enough!
    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant GAS_PRICE = 1;

    address public ADMINISTRATOR = makeAddr("Admin");
    address Alice = makeAddr("Alice");
    address Bob = makeAddr("Bob");
    address Charlie = makeAddr("Charlie");
    address Treasury = makeAddr("Treasury");

    CurveFactory.CreateParams params =
        CurveFactory.CreateParams({
            name: "MyToken",
            symbol: "MTK",
            migrationMcapEth: Constants.CURVE_LIMIT, // 25 ETH as full FDV
            minHoldingForReferrer: 1e18, // Minimum holding to refer (1 token)
            vETH: Constants.CURVE_VETH
        });

    // 648,771,266.540642722117202269 32,500
    // 799,835,914.685891995986059639
    function setUp() external {
        vm.deal(ADMINISTRATOR, STARTING_USER_BALANCE);
        vm.deal(Alice, STARTING_USER_BALANCE); // creator
        vm.deal(Bob, STARTING_USER_BALANCE); // buyer
        vm.deal(Charlie, STARTING_USER_BALANCE); // referrer

        //math = new CurveMath();
        // since we have added the prank logic in the deployment script, we can just call the deployment function here
        ContractsDeployment deployer = new ContractsDeployment();
        (factory, bondingCurveImpl) = deployer.deployFactoryAndBondingCurve();

        console.log("Factory", address(factory));
        console.log("Curve Implementation", address(bondingCurveImpl));
        console.log("Owner of Factory:", factory.owner());

        vm.startPrank(Alice);
        (address deployedBondingCurveAddr, address tokenAddress) = factory
            .createCurve(params);

        // creator
        bondingCurve = BondingCurve(payable(deployedBondingCurveAddr)); // <-- ✅ initialize curve instance here
        token = CurveToken(tokenAddress); // <-- ✅ initialize token instance here
        console.log("Deployed Curve at:", deployedBondingCurveAddr);
        console.log("Deployed Token at:", tokenAddress);
        console.log("this contract:", address(this));
        console.log("Alice:", Alice);
        console.log(
            "================================setUp Ends================================"
        );
        //console.log("Owner of Curve:", bondingCurve.getOwner());
        vm.stopPrank();
    }

    // function test_FindIdealVETH() public {
    //     uint256 totalSupply = 1_000_000_000 * 1e18;
    //     uint256 allocationPercent = 80;
    //     uint256 curveLimit = 100; // 100 ETH

    //     uint256 idealVETH = math.findIdealVETH(
    //         totalSupply,
    //         allocationPercent,
    //         curveLimit
    //     );

    //     console.log("Ideal vETH (1e18):", idealVETH);
    //     console.log("Ideal vETH (ETH):", idealVETH / 1e18);
    // }
    /*
    function testParamsSetup() public view {
        assertEq(Alice, bondingCurve.creator());
        assertEq(factory.superAdmin(), bondingCurve.factory().superAdmin());
        assertEq(address(factory), address(bondingCurve.factory()));
        assertEq(
            bondingCurve.minHoldingForReferrer(),
            params.minHoldingForReferrer
        );
        assertEq(bondingCurve.curveLimit(), params.migrationMcapEth);
        assertEq(bondingCurve.migrationTriggered(), false);
        console.log("curve factory address:", address(bondingCurve.factory()));
        console.log("curve implementation address:", address(bondingCurveImpl));
        console.log("================================testParamsSetup Ends================================");
    }

    function testCurveCurrentData() public view {
        uint256 curveLimit = bondingCurve.curveLimit();
        console.log("Curve Limit:", curveLimit);
        uint256 totalSupply = token.totalSupply();
        console.log("Total Supply:", totalSupply);
        uint256 contractBalance = address(bondingCurve).balance;
        console.log("Contract Balance:", contractBalance);
        uint256 tokensBefore = bondingCurve.tokensBefore();
        // console.log("Tokens Before:", tokensBefore);
        // uint256 tokensAfter = bondingCurve.tokensAfter();
        // console.log("Tokens After:", tokensAfter);
        uint256 vEth = bondingCurve.vETH();
        console.log("vEth:", vEth);
        uint256 vToken = bondingCurve.vToken();
        console.log("vToken:", vToken);
        uint256 k = bondingCurve.k();
        console.log("k:", k);
        console.log("========================testCurveCurrentData Ends==========================");
    }
*/

    function testBuyMinTokensOut() public {
        vm.startPrank(Bob);
        uint256 bobInitialBalance = Bob.balance;
        //10000000000000000000
        console.log("Bob initial eth balance:", bobInitialBalance);
        uint256 treasuryBalance = Treasury.balance;
        console.log("Treasury initial eth balance:", treasuryBalance / 1e18);

        // Token Balance before buy
        uint256 curevTokenBalance = token.balanceOf(address(bondingCurve));
        console.log(
            "Curve Token Balance before buy:",
            curevTokenBalance / 1e18
        );
        uint256 tokenBalanceBefore = token.balanceOf(Bob);
        //uint256 tokensOut = bondingCurve.getTokensOut(SEND_VALUE);
        //uint256 expectedTokens = bondingCurve.getTokensOut(SEND_VALUE);
        //uint256 minTokensOut = (expectedTokens * 98) / 100; // Apply 1% slippage buffer

        // 224,460,431.654676258992805756
        // 219,971,223
        // 0.027500000000000000 - 0.110000000000000000
        // 648,771,266.540642722117202269
        // console.log("Tokens out for Bob:", minTokensOut); //30,028,873.917228103946102022 29,428,296.438883541867179981
        // assert(minTokensOut > 0);
        // 1,000,000,000.000000000000000000
        // 0.137500000000000000
        // 609,375,000.000000000000000000
        // 2.925000000000000000
        // 90.000000000000000000
        // 295,268,138.801261829652996848
        // 0.300000000000000000
        // 0.550000000000000000
        // 400,000,000.000000000000000004
        // 799,920,000.000000000007999203
        // 799,917,948.928336081197739680
        // 799,908,833.181531084048113392
        // 799,835,914.685891995986059639
        // 799,180,245.977441394073606764

        // 799180245977441394073606764
        // 799589912882117894961289823
        // 799726561865805108706175398
        // 799794903874009449824509370
        // 799835914685891995986059639
        // 799863257563779663507629174
        // 799882789335441171796035612
        // 3,265,306.122448979591836735

        // 783,196,641.057892566192134628
        // 0.002000200020002000
        // 2051071663918810259523
        // 0.500000000000000000

        //9115.746804997149626288 1.950000000000000000
        // 2,836,879.432624113475177305

        for (uint256 i = 0; i < 5; i++) {
            uint256 expectedTokens = bondingCurve.getTokensOut(SEND_VALUE);
            uint256 minTokensOut = (expectedTokens * 98) / 100; // Apply 1% slippage buffer

            console.log("mins Tokens out for Bob:", minTokensOut); //30,028,873.917228103946102022 29,428,296.438883541867179981
            console.log("mins Tokens out for Bob (UI):", minTokensOut / 1e18); //30,028,873.917228103946102022 29,428,296.438883541867179981
            assert(minTokensOut > 0);

            bondingCurve.buy{value: SEND_VALUE}(minTokensOut, address(0)); // uint256 minTokensOut, address _referrer
            console.log("Bob bought tokens in the loop:", i + 1);
            console.log("raisedEth: ", bondingCurve.raisedETH());
        }

        // 189,418,907.198612315698178667
        // 250,000,000.000000000000000004
        // 0.250000000000000000
        // 33,949,945.593035908596300327
        // 29,248,948.865900131714016528

        // uint256 expectedTokens = bondingCurve.getTokensOut(SEND_VALUE);
        // uint256 minTokensOut = (expectedTokens * 98) / 100; // Apply 1% slippage buffer

        // bondingCurve.buy{value: SEND_VALUE}(minTokensOut, address(0));

        // 1.950000000000000000 * 5 = 9.750000000000000000
        // tokensOut = 41010811882546161550269
        // 71,070,615.034168564920273349

        // 1950000000000000000 - 394936708860759493670886076 - 394936708860759493670886076
        // 1950000000000000000 - 133876850461274404634198670 - 528813559322033898305084746
        // 1950000000000000000 - 67364784627010687682176401 - 596178343949044585987261147
        // 1950000000000000000 - 40556349928506434420902119 - 636734693877551020408163266
        // 1950000000000000000 - 27095093356491532783326097 - 663829787234042553191489363
        // 1950000000000000000 - 19381891598074235129678522 - 683211678832116788321167885
        // 1950000000000000000 - 14551899442643595065413587 - 697763578274760383386581472
        // 1950000000000000000 - 11327330816148707522509440 - 709090909090909090909090912
        // 1950000000000000000 - 9067658684026970471983260 - 718158567774936061381074172
        // 1950000000000000000 - 7422827573901147921251413 - 725581395348837209302325585
        // 500000000000000000 - 1691331923890063424947146 - 727272727272727272727272731

        uint256 bobFinalBalance = Bob.balance;
        uint256 tokenBalanceAfter = token.balanceOf(Bob);
        uint256 curevTokenBalanceAfter = token.balanceOf(address(bondingCurve));
        console.log(
            "Curve Token Balance after buy:",
            curevTokenBalanceAfter / 1e18
        );
        console.log("Bob final balance:", bobFinalBalance);
        console.log("Bob token balance before buy:", tokenBalanceBefore);
        console.log(
            "Bob token balance after buy:",
            tokenBalanceAfter,
            tokenBalanceAfter / 1e18
        );

        // 9.750000000000000000
        // 5.850000000000000000
        // 71,070,615.034168564920273349
        // 0.050000000000000000
        //assert(tokenBalanceAfter > tokenBalanceBefore);
        assert(bobFinalBalance < bobInitialBalance);

        // 2.925000000000000000
        // 2.937575461727245041
        // 280,147,676
        // 719,852,323
        address refOff = bondingCurve.referrerOf(Bob);
        console.log("Bob's referrer:", refOff);
        uint256 treasuryBalanceAfter = Treasury.balance;
        uint256 curveFinalBalance = address(bondingCurve).balance;
        console.log("Curve final balance:", curveFinalBalance);
        //console.log("Curve final balance (UI):", curveFinalBalance / 1e18);
        // 1.950000000000000000
        // 71,070,615.034168564920273349
        console.log("Treasury final balance:", treasuryBalanceAfter);

        // uint256 tokenAfter = bondingCurve.tokensAfter();
        // uint256 tokenBefore = bondingCurve.tokensBefore();
        // console.log("Tokens Before:", tokenBefore);
        // console.log("Tokens After:", tokenAfter);

        //console.log("New raised eth", bondingCurve.newRaisedETH());
        uint256 tokensSold = bondingCurve.tokensSold();
        console.log("tokens Sold", tokensSold, tokensSold / 1e18);
        // uint256 ethWhole = treasuryBalanceAfter / 1e18;
        // uint256 ethFraction = treasuryBalanceAfter % 1e18;

        // console.log(
        //     "Treasury final balance (ETH): %s.%018s",
        //     ethWhole,
        //     ethFraction
        // ); 0.05000000000000000
        //vm.stopPrank();

        console.log(
            "========================testBuyMinTokensOut Ends=========================="
        );
    }

    function testSellTokens() public {
        //vm.startPrank(Bob);
        testBuyMinTokensOut(); // this will ensure Bob has tokens to sell
        //testBuyMinTokensOut();
        // Initial balances
        uint256 bobInitialEthBalance = Bob.balance;
        console.log(
            "Bob initial ETH balance before Sell:",
            bobInitialEthBalance
        );

        uint256 treasuryInitialEthBalance = Treasury.balance;
        console.log(
            "Treasury initial ETH balance before Sell:",
            treasuryInitialEthBalance / 1e18
        );

        uint256 bobInitialTokenBalance = token.balanceOf(Bob);
        //224,460,431.654676258992805756
        // 22,446,043.165467625899280575
        console.log(
            "Bob initial token balance before sell:",
            bobInitialTokenBalance / 1e18
        ); //

        uint256 curveInitialTokenBalance = token.balanceOf(
            address(bondingCurve)
        );
        console.log(
            "Curve token balance before sell:",
            curveInitialTokenBalance / 1e18
        );

        // Amount of tokens Bob wants to sell (e.g., 10% of his balance)
        uint256 tokensToSell = bobInitialTokenBalance / 10;
        require(tokensToSell > 0, "Bob has no tokens to sell");
        console.log("Bobs tokens to sell: ", tokensToSell);

        // Calculate minimum ETH out (simulate slippage, e.g., 2% slippage tolerance)
        uint256 expectedEthOut = bondingCurve.getMinEthOut(tokensToSell);
        // 0.127698724735322427
        uint256 minEthOut = (expectedEthOut * 98) / 100; // 2% slippage buffer

        console.log("Tokens to sell:", tokensToSell);
        console.log("Tokens to sell UI: ", tokensToSell / 1e18);
        console.log("Expected ETH out:", expectedEthOut);
        //0.123264867018627355
        // 0.100908955075206694
        // 6.617783837179247675
        console.log("Minimum ETH out (with 2% slippage):", minEthOut);

        // 0.067245727662117741
        // 0.068618089451140553

        // Approve bondingCurve to transfer tokens on Bob's behalf
        token.approve(address(bondingCurve), tokensToSell);

        // Perform sell
        bondingCurve.sell(tokensToSell, minEthOut);

        // Balances after sell
        uint256 bobFinalEthBalance = Bob.balance;
        uint256 bobFinalTokenBalance = token.balanceOf(Bob);
        uint256 curveFinalTokenBalance = token.balanceOf(address(bondingCurve));
        uint256 treasuryFinalEthBalance = Treasury.balance;

        console.log("Bob final ETH balance:", bobFinalEthBalance);
        console.log("Bob final token balance:", bobFinalTokenBalance / 1e18);
        // 27,025,986
        // 3,002,887
        console.log(
            "Curve token balance after sell:",
            curveFinalTokenBalance / 1e18
        );
        console.log(
            "Treasury final ETH balance:",
            treasuryFinalEthBalance / 1e18
        );

        // 96.617783837179247675
        // 79,983,591.468589199598605963 - 6.617783837179247675
        // Assertions
        assert(bobFinalEthBalance > bobInitialEthBalance); // Bob received ETH
        assert(bobFinalTokenBalance < bobInitialTokenBalance); // Bob's tokens decreased
        assert(curveFinalTokenBalance > curveInitialTokenBalance); // Curve got tokens back

        testBuyMinTokensOut();

        // MIGRATION DETAILING
        // 241,797,923.066205414825716807
        // 9.796044303797468355
        // 0.000000040513351726

        vm.stopPrank();
    }

    /*
    function testBuyToHitCurve() public {
        //vm.startPrank(Bob);
        testBuyMinTokensOut();
        (
            uint256 ethToSeed,
            uint256 tokensToSeed,
            uint256 lastPrice
        ) = bondingCurve.getLiquiditySeedAmounts();
        //testBuyMinTokensOut();

        console.log("eth to seed:", ethToSeed);
        console.log("tokens to seed:", tokensToSeed);
        console.log("last price:", lastPrice);
    }

    */

    // 241,797,923.066205414825716807
    // 9.796044303797468355
    // 0.000000040513351726

    // function testMigration() public {
    //     bondingCurve.migrateToLP();
    // }
    // 5.362500000000000000
    /*
    function testFundFailsWithoutEnoughETH() public skipZkSync {
        vm.expectRevert();
        fundMe.fund();
    }
    */

    // 0.831758034026465028
    // 5.500000000000000000
    // 6.612500000000000000

    /*
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

    */
}
