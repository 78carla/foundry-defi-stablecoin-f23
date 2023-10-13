// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is StdCheats, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 20 ether;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    uint256 private constant LIQUIDATION_BONUS = 10; //this means 10% bonus

    function setUp() external {
        deployer = new DeployDSC();
        //Il deploy ritorna dsc e dsce
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////
    /// Constructor Test
    //////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedsAddresses;

    function testrevertIfTokenLenghtDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedsAddresses.push(ethUsdPriceFeed);
        priceFeedsAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddresesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedsAddresses, address(dsc));
    }

    //////////////////////
    /// Price Test
    //////////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        //15e18 * 2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function getTokenAmountFromDSCAmount() public {
        uint256 usdAmount = 100 ether;

        //2000$ ETH, 100$
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    ////////////////////////////
    /// Deposit Collateral Test
    ///////////////////////////
    function testRevertsIfCollateralIsZero() public {
        console.log("I'm here");
        vm.startPrank(USER);
        console.log("USER: ", USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfCollateralIsNotApproved() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUSd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUSd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    //////////////////////
    /// Mint DSC Test
    //////////////////////
    function testMintDSC() public {
        vm.startPrank(USER);
        // First, approve and deposit collateral
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Then, mint DSC
        uint256 amountDSCToMint = 1 ether;
        dsce.mintDSC(amountDSCToMint);

        uint256 actualDSCMinted = dsce.s_DSCMinted(USER);
        assertEq(actualDSCMinted, amountDSCToMint);
        vm.stopPrank();
    }

    //////////////////////
    /// Burn DSC Test
    //////////////////////
    /* function testBurnDSC() public {
        vm.startPrank(USER);
        // First, approve and deposit collateral
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Then, mint DSC
        uint256 amountDSCToMint = 5 ether; // Make sure this is less than the value of the deposited collateral
        dsce.mintDSC(amountDSCToMint);

        // Finally, burn DSC
        uint256 amountDSCToBurn = 4 ether;
        dsce.burnDSC(amountDSCToBurn);

        uint256 actualDSCMinted = dsce.s_DSCMinted(USER);
        assertEq(actualDSCMinted, 0);
        vm.stopPrank();
    } */

    //////////////////////
    /// Redeem Collateral Test
    //////////////////////
    function testRedeemCollateral() public {
        vm.startPrank(USER);
        // First, approve and deposit collateral
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        // Then, mint DSC
        uint256 amountDSCToMint = 5 ether; // Make sure this is less than the value of the deposited collateral
        dsce.mintDSC(amountDSCToMint);

        uint256 amountCollateralToRedeem = 2 ether;
        dsce.redeemCollateral(weth, amountCollateralToRedeem);
        uint256 actualCollateral = dsce.s_collateralDeposits(USER, weth);
        assertEq(actualCollateral, AMOUNT_COLLATERAL - amountCollateralToRedeem);
        vm.stopPrank();
    }
}
