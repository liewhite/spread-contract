// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Spread.sol";
import {MockErc20} from "./MockToken.sol";

contract SpreadTest is Test {
    Spread public spread;
    MockErc20 public token;

    function setUp() public {
        spread = new Spread();
        token = new MockErc20();
    }

    function testWithdrawEth() public {
        vm.prank(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081);
        vm.deal(address(spread), 100);
        spread.withdrawEth(100);
        assertEq(address(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081).balance, 100);
    }

    function testWithdrawToken() public {
        token.mint(address(spread), 100);
        vm.prank(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081);
        spread.withdrawToken(address(token),100);
        assertEq(token.balanceOf(address(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081)), 100);
    }
}
