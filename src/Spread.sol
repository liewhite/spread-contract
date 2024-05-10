// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./interface/IUniswapV2Pair.sol";

contract Spread is Ownable(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081) {
    function withdrawToken(address _token, uint256 amount) public onlyOwner {
        IERC20(_token).transfer(owner(), amount);
    }

    function withdrawEth(uint256 amount) public onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    // 搬砖函数
    // 接收step[], 每一步表示次swap, 第一步总是闪电贷
    function moveSpread() public onlyOwner {}
    /*
     闪电贷和swap逻辑不同， 闪电贷是策略先指定amountOut，拿到token, 最后再还钱
     多还的钱是肯定不退的， 所以， 必须自己计算还钱的数量
     */

    // univ2闪电贷逻辑, 直接把钱借到下一个池子去
    // amountOut来自策略二分查找的结果， amountIn模拟时合约自己计算， 广播时由策略根据模拟log指定
    // 模拟时amountIn=0， 通过getAmountIn计算
    // 模拟完成后， 可以通过log拿到getAmountIn， 正式发送交易时就不再需要指定getAmountIn了
    function loanUniv2(
        address pool,
        address to,
        uint256 amountOut,
        uint256 amountIn,
        bool is_token0
    ) internal {
        if(amountIn == 0) {
            
        }

        uint256 amount0 = 0;
        uint256 amount1 = 0;
        if (is_token0) {
            amount0 = amountOut;
        }else {
            amount1 = amountOut;
        }
        // todo 合约内计算amountIn
        IUniswapV2Pair(pool).swap(amount0, amount1, to, data);

    }

    // univ3闪电贷逻辑, 直接把钱借到下一个池子去
    // amountSpecific也由策略指定, 传入负数， 表示借多少token
    // amountIn模拟的时候通过quoter合约计算， 广播的时候策略指定
    function loanUniv3(
        address pool,
        address to,
        uint256 amount,
        bool is_token0
    ) internal {}

    // univ2 swap 逻辑
    // 这里假设amountIn已经进入池子了
    // NOTE: amountOut是必须知道的, 如果是0 ， 那就通过getAmountOut计算
    function swap_univ2() internal {
    }

    // univ2 swap 逻辑, swap一定是知道amountIn的， 那么amountOut就会通过函数返回值拿到
    function swap_univ3() internal {

    }
}
