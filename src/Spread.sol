// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Spread is Ownable(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081) {
    function withdraw_token(address _token, uint256 amount) public onlyOwner {
        IERC20(_token).transfer(owner(), amount);
    }

    function withdraw_eth(uint256 amount) public onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    // 搬砖函数
    function move_spread() public onlyOwner {}
}
