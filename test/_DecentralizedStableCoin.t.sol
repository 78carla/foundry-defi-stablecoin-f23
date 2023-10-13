// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DecentralizedStableCoinTest is StdCheats, Test {
    DecentralizedStableCoin decentralizedStableCoin;

    uint256 public STARTING_TOKEN_SUPPLY = 0 ether;
    address bob = makeAddr("bob");

    uint256 public STARTING_BALANCE = 100 ether;

    function setUp() external {
        decentralizedStableCoin = new DecentralizedStableCoin();
        console.log("Decentralized Stable Coin address: ", address(decentralizedStableCoin));
    }

    function testInitialSupply() public {
        assertEq(decentralizedStableCoin.totalSupply(), STARTING_TOKEN_SUPPLY);
        console.log("Total supply: ", decentralizedStableCoin.totalSupply());
    }

    function testUsersCantMint() public {
        vm.prank(bob);
        vm.expectRevert();
        bool minted = decentralizedStableCoin.mint(address(this), 1);
        console.log("Minted: ", minted);
    }

    function testUsersCantBurn() public {
        vm.prank(bob);
        vm.expectRevert();
        decentralizedStableCoin.burn(1);
    }

    function testOnlyTheOwnerCanMint() public {
        uint256 totalSupplyBeforeMint = decentralizedStableCoin.totalSupply();
        console.log("Total supply before mint: ", totalSupplyBeforeMint);
        uint256 mintAmount = 50 ether;

        // Check that the owner can mint tokens
        decentralizedStableCoin.mint(address(this), mintAmount);
        assertEq(decentralizedStableCoin.balanceOf(address(this)), mintAmount);
        assertEq(decentralizedStableCoin.totalSupply(), totalSupplyBeforeMint + mintAmount);
        uint256 totalSupplyAfterMint = decentralizedStableCoin.totalSupply();
        console.log("Total supply before mint: ", totalSupplyAfterMint);
    }
}
