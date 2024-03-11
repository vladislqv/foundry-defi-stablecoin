// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {console} from "forge-std/console.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address ethUsdPriceFeed;
    address weth;
    address wbtcUsdPriceFeed;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public AMOUNT_DSC_MINTED;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        AMOUNT_DSC_MINTED = engine.getUsdValue(weth, AMOUNT_COLLATERAL) / 2 - 1 ether;
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](2);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /////////////////
    // Price Tests //
    /////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedEthUsdValue = 60000e18;
        uint256 actualEthUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualEthUsd, expectedEthUsdValue);

        uint256 btcAmount = 2e8;
        uint256 expectedBtcUsdValue = 140000e8;
        uint256 actualBtcUsd = engine.getUsdValue(wbtc, btcAmount);
        assertEq(actualBtcUsd, expectedBtcUsdValue);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedEthAmount = 0.025 ether;
        uint256 actualEthAmount = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualEthAmount, expectedEthAmount);
    }

    //////////////////////
    // Collateral Tests //
    //////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnnaprovedCollateral() public {
        ERC20Mock token = new ERC20Mock();
        token.mint(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
        engine.depositCollateral(address(token), STARTING_ERC20_BALANCE);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testCanRedeemCollateral() public depositedCollateral {
        uint256 userBalanceBeforeRedeem = ERC20Mock(weth).balanceOf(USER);
        vm.prank(USER);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = 0;
        uint256 actualDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(expectedDepositAmount, actualDepositAmount);

        uint256 actualUserBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalanceBeforeRedeem + AMOUNT_COLLATERAL, actualUserBalance);
    }

    function testRevertsIfUserTriesToRedeemMoreThanTheyHave() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__CannotRedeemMoreThanDeposited.selector);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL + 1);
    }

    ///////////////
    // Dsc Tests //
    ///////////////

    modifier mintDsc() {
        vm.startPrank(USER);
        engine.mintDsc(AMOUNT_DSC_MINTED);
        vm.stopPrank();
        _;
    }

    function testCanMintDsc() public depositedCollateral {
        uint256 userBalanceBeforeMint = DecentralizedStableCoin(dsc).balanceOf(USER);
        vm.startPrank(USER);
        engine.mintDsc(AMOUNT_DSC_MINTED);
        vm.stopPrank();

        uint256 userBalanceAfterMint = DecentralizedStableCoin(dsc).balanceOf(USER);
        assertEq(userBalanceBeforeMint + AMOUNT_DSC_MINTED, userBalanceAfterMint);
    }

    function testCannotMintDscIfCollateralValueIsUnderLiquidationThreshold() public depositedCollateral {
        vm.startPrank(USER);
        uint256 collateralValueInUsd = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        vm.expectRevert();
        engine.mintDsc((collateralValueInUsd * 51) / 100);
        vm.stopPrank();
    }

    function testBurnDsc() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintDsc(AMOUNT_DSC_MINTED);
        uint256 userBalanceBeforeBurn = dsc.balanceOf(USER);

        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        engine.burnDsc(AMOUNT_DSC_MINTED);
        vm.stopPrank();

        uint256 userBalanceAfterBurn = dsc.balanceOf(USER);

        assertEq(userBalanceBeforeBurn - AMOUNT_DSC_MINTED, userBalanceAfterBurn);
    }

    function testDepositCollateralAndMintDsc() public {
        uint256 dscBalanceBefore = dsc.balanceOf(USER);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();
        uint256 dscBalanceAfter = dsc.balanceOf(USER);
        assertEq(dscBalanceBefore + AMOUNT_DSC_MINTED, dscBalanceAfter);
    }

    function testRedeemCollateralForDsc() depositedCollateral mintDsc public {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    modifier updateEthPrice(int256 newEthPrice) {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newEthPrice);
        _;
    }

    modifier mintDscToLiquidator() {
        vm.prank(address(engine));
        dsc.mint(LIQUIDATOR, AMOUNT_DSC_MINTED);
        _;
    }

    function testRevertsIfUserHealthFactorIsOk() public depositedCollateral mintDsc {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, 1);
    }

    function testHealthFactorIsBrokenAfterUpdatingEthPrice() depositedCollateral mintDsc public {
        uint256 healthFactorBefore = engine.getHealthFactor(USER);
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);
        uint256 healthFactorAfter = engine.getHealthFactor(USER);
        assert(healthFactorBefore > healthFactorAfter);
    }

    function testRevertIfHealthFactorNotImproved() public depositedCollateral mintDsc updateEthPrice(2000e8) mintDscToLiquidator {
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        engine.liquidate(weth, USER, 1);
        vm.stopPrank();
    }

    function testSuccessFullLiquidation() public depositedCollateral mintDsc updateEthPrice(3000e8) mintDscToLiquidator {
        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        engine.liquidate(weth, USER, AMOUNT_DSC_MINTED / 2);
        vm.stopPrank();
    }

    function testRevertIfTheLiquidatorHealthFactorIsBroken() public depositedCollateral mintDsc {
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_DSC_MINTED);
        vm.stopPrank();

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(3000e8);

        vm.startPrank(LIQUIDATOR);
        dsc.approve(address(engine), AMOUNT_DSC_MINTED);
        vm.expectRevert();
        engine.liquidate(weth, USER, AMOUNT_DSC_MINTED / 2);
        vm.stopPrank();
    }
}
