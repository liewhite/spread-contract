// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../src/Spread.sol";
import "../src/interfaces/IERC20.sol";
import "../lib/forge-std/src/Test.sol";
import "./TestSpreadCommon.sol";

contract Univ2FlashTest is TestSpreadCommon {
    address token0 = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // weth
    address token1 = 0xb50a8e92CB9782C9b8f3c88e4Ee8A1d0AA2221D7; // yaks
    address pool = 0x716fBdA28320849Daa418996CA9403Fe9d1fA564; 

    function testV2Flash() public {
        writeTokenBalance(address(spread), address(token0), 100000000);
        spread.loanUniv2(pool, address(spread), 10000000, 0, false);
        uint256 balance = IERC20(address(token1)).balanceOf(address(spread));
        assert(balance > 0);
    }
}
