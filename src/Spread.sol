// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Callee.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "../lib/forge-std/src/Test.sol";

contract Spread is
    Ownable(0x7Ca9659FeAd658B7f0409803E0D678d75C49C081),
    IUniswapV2Callee,
    IUniswapV3SwapCallback,
    Test
{
    struct SwapItem {
        uint8 protocol;
        address pool;
        uint256 amountIn;
        uint256 amountOut;
        bool isToken0Out;
    }
    // 临时变量， 验证回调是否合法
    address private tmpPoolAddr;

    function withdrawToken(address _token, uint256 amount) public onlyOwner {
        IERC20(_token).transfer(owner(), amount);
    }

    function withdrawEth(uint256 amount) public onlyOwner {
        payable(msg.sender).transfer(amount);
    }

    function parsePathItem(
        bytes memory data
    ) internal pure returns (SwapItem memory) {
        // protocol 0 univ2 1 univ3
        // protocol, pool, next_pool, amountBorrow, amountRepay, isToken0Out
        (
            uint8 protocol, // protocol
            address pool,
            uint256 amountIn,
            uint256 amountOut,
            bool isToken0Out
        ) = abi.decode(data, (uint8, address, uint256, uint256, bool));
        return SwapItem(protocol, pool, amountIn, amountOut, isToken0Out);
    }

    // 执行swap步骤， flash的callback都转发到这里
    function swapsAndRepay(bytes memory data) internal {
        (
            address repayPool,
            address repayToken,
            uint256 repayAmount,
            bytes[] memory swaps
        ) = abi.decode(data, (address, address, uint256, bytes[]));
        uint swapsLen = swaps.length;
        SwapItem[] memory swapItems = new SwapItem[](swapsLen);
        // 先全部parse
        for (uint i = 0; i < swapsLen; i++) {
            swapItems[i] = parsePathItem(swaps[i]);
        }

        for (uint i = 0; i < swapsLen; i++) {
            SwapItem memory item = swapItems[i];
            address receiver;
            if (i == swapsLen - 1) {
                receiver = address(this);
            } else {
                receiver = swapItems[i + 1].pool;
            }
            if (item.protocol == 0) {
                swap_univ2(
                    item.pool,
                    receiver,
                    item.amountIn,
                    item.amountOut,
                    item.isToken0Out
                );
            } else if (item.protocol == 1) {
                swap_univ3(
                    item.pool,
                    receiver,
                    item.amountIn,
                    item.amountOut,
                    item.isToken0Out
                );
            } else {
                revert("unknown protocol");
            }
            // repay
            IERC20(repayToken).transfer(repayPool, repayAmount);
        }
    }

    // 搬砖函数
    // 搬砖分3步
    // 1. 闪电贷, 由策略发起交易
    // 2. swaps， 通过callback触发,然后循环swap, 最后一个swap的receiver是本合约(策略应该已经填好了)
    // 3. repay, callback中swap完后， 调用repay函数
    function startSpread(
        address flashPool,
        uint8 flashProtocol,
        uint256 flashBorrow,
        uint256 flashRepay,
        bool isBorrowToken0,
        bytes[] calldata swaps 
    ) public onlyOwner {
        // 需要
        SwapItem memory firstSwap = parsePathItem(swaps[0]);

        // 处理闪电贷
        if (flashProtocol == 0) {
            loanUniv2(
                flashPool,
                firstSwap.pool,
                flashRepay,
                flashBorrow,
                isBorrowToken0,
                swaps
            );
        } else if (flashProtocol == 1) {
            loanUniv3(
                flashPool,
                firstSwap.pool,
                flashRepay,
                flashBorrow,
                isBorrowToken0,
                swaps
            );
        } else {
            revert("unknown protocol");
        }
    }

    function loanUniv2(
        address pool,
        address to,
        uint256 amountRepay, // 模拟时为0
        uint256 amountBorrow,
        bool isToken0Out, // 是否借出的token0
        bytes[] memory path
    ) public {
        // 闪电贷不可能是最后一步
        require(path.length > 0);
        // 回调需要知道归还哪个token, 借0还1， 借1还0
        address repayToken;
        if (isToken0Out) {
            repayToken = IUniswapV2Pair(pool).token1();
        } else {
            repayToken = IUniswapV2Pair(pool).token0();
        }
        // 回调需要知道归还多少
        uint256 repayAmount = amountRepay;
        // 合约内计算amountIn
        if (repayAmount == 0) {
            (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pool)
                .getReserves();
            if (isToken0Out) {
                repayAmount = UniswapV2Library.getAmountIn(
                    amountBorrow,
                    reserve1,
                    reserve0
                );
            } else {
                repayAmount = UniswapV2Library.getAmountIn(
                    amountBorrow,
                    reserve0,
                    reserve1
                );
            }
        }

        uint256 amount0 = 0;
        uint256 amount1 = 0;
        if (isToken0Out) {
            amount0 = amountBorrow;
        } else {
            amount1 = amountBorrow;
        }
        tmpPoolAddr = pool;
        IUniswapV2Pair(pool).swap(
            amount0,
            amount1,
            to,
            abi.encode(pool, repayToken, repayAmount, path)
        );
    }

    function uniswapV2Call(
        address,
        uint,
        uint,
        bytes calldata data
    ) external override {
        require(msg.sender == tmpPoolAddr);
        swapsAndRepay(data);
    }

    // univ3闪电贷逻辑, 直接把钱借到下一个池子去
    // amountSpecific也由策略指定, 传入负数， 表示借多少token
    // amountIn模拟的时候通过quoter合约计算， 广播的时候策略指定
    function loanUniv3(
        address pool,
        address to,
        uint256 amountOut,
        uint256 amountIn,
        bool isToken0Out, // 是否借出的token0
        bytes[] memory conts
    ) internal {}

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes calldata data
    ) external {
        swapsAndRepay(data);
    }

    // univ2 swap 逻辑
    // 这里假设amountIn已经进入池子了
    // NOTE: amountOut是必须知道的, 如果是0 ， 那就通过getAmountOut计算
    function swap_univ2(
        address pool,
        address receiver,
        uint256 amountIn,
        uint256 amountOut,
        bool isToken0Out
    ) internal {}

    // univ2 swap 逻辑, swap一定是知道amountIn的， 那么amountOut就会通过函数返回值拿到
    function swap_univ3(
        address pool,
        address receiver,
        uint256 amountIn,
        uint256 amountOut,
        bool isToken0Out
    ) internal {}
}
