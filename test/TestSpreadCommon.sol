// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../src/Spread.sol";
import "../src/interfaces/IERC20.sol";
import {MockErc20} from "./MockToken.sol";
import "../lib/forge-std/src/Test.sol";

contract TestSpreadCommon is Test {
    using stdStorage for StdStorage;
    StdStorage sto;

    Spread public spread;

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
    }
}
