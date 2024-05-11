// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../src/Spread.sol";
import "../src/interfaces/IERC20.sol";
import {MockErc20} from "./MockToken.sol";
import "../lib/forge-std/src/Test.sol";

contract WithdrawTest is Test {
    using stdStorage for StdStorage;
    StdStorage sto;

    Spread public spread;
    MockErc20 public token;

    function writeTokenBalance(
        address receiver,
        address tk,
        uint256 amt
    ) internal {
        sto
            .target(tk)
            .sig(IERC20(tk).balanceOf.selector)
            .with_key(receiver)
            .checked_write(amt);
    }

    function setUp() public {
        spread = new Spread();
        token = new MockErc20();
    }

    function testWithdrawEth() public {
        vm.prank(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081);
        vm.deal(address(spread), 100);
        spread.withdrawEth(100);
        assertEq(
            address(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081).balance,
            100
        );
    }

    function testWithdrawToken() public {
        token.mint(address(spread), 100);
        vm.prank(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081);
        spread.withdrawToken(address(token), 100);
        assertEq(
            token.balanceOf(
                address(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081)
            ),
            100
        );
    }
    function testMockERC20Balance() public {
        writeTokenBalance(address(this), address(token), 100);
        uint256 balance = IERC20(address(token)).balanceOf(address(this));
        assert(balance == 100);
    }

}
