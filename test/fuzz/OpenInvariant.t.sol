// SPDX-License-Identifier: MIT

///*
//La commentiamo perchè non la usiamo più
///*

//Have our invariant aka our properties

//What are our invariant?
//1. The total supply of DSC (debt) should be less then the total value of collateral
//2. Getter function should never revert <-- evergreen invariant

pragma solidity ^0.8.18;
/*
import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();

        //Definisco il target contract per i fuzz test
        targetContract(address(dsce));
    }

    function invariant_protocolMustHaveMoreValueThenTotalSupply() public view {
        //get the value of all the collateral in the protocol
        //compare it to the total debt (dsc)

        //Total supply dei DSC
        uint256 totalSupply = dsc.totalSupply();
        //Totale dei weth depositati
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        //Totale dei wbtc depositati
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        //Calcola il valore in usd dei weth
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        //Calcola il valore in usd dei wbtc
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalSupply);
    }
}
 */
