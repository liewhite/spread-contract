// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockErc20 is ERC20 {
    constructor()
        ERC20("MyToken", "MTK")
    {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}