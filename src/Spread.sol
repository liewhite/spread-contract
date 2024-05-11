// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/TickMath.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Callee.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./interfaces/IUniswapV3PoolActions.sol";
import "./interfaces/IUniswapV3PoolImmutables.sol";
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
        // uint256 amountIn; // 第一个amountIn来自flash ， 后面的in都是前一个的out
        // uint256 amountOut;
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
            // uint256 amountIn,
            // uint256 amountOut,
            bool isToken0Out
        ) = abi.decode(data, (uint8, address, bool));
        return SwapItem(protocol, pool, isToken0Out);
    }

    // 执行swap步骤， flash的callback都转发到这里
    function swapsAndRepay(bytes memory data) internal {
        (
            address repayPool,
            address repayToken,
            uint256 borrowAmount,
            uint256 repayAmount,
            bytes[] memory swaps
        ) = abi.decode(data, (address, address, uint256, uint256, bytes[]));

        uint swapsLen = swaps.length;
        if (swapsLen > 0) {
            SwapItem[] memory swapItems = new SwapItem[](swapsLen);

            // 先全部parse
            for (uint i = 0; i < swapsLen; i++) {
                swapItems[i] = parsePathItem(swaps[i]);
            }
            uint256 amountIn = borrowAmount;
            for (uint i = 0; i < swapsLen; i++) {
                SwapItem memory item = swapItems[i];
                if (item.protocol == 0) {
                    amountIn = swap_univ2(
                        item.pool,
                        amountIn,
                        item.isToken0Out
                    );
                } else if (item.protocol == 1) {
                    amountIn = swap_univ3(
                        item.pool,
                        amountIn,
                        item.isToken0Out
                    );
                } else {
                    revert("unknown protocol");
                }
            }
        }

        // repay
        IERC20(repayToken).transfer(repayPool, repayAmount);
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
        bool isBorrowToken0,
        bytes[] calldata swaps
    ) public {
        require((swaps.length > 0));
        // 处理闪电贷
        if (flashProtocol == 0) {
            loanUniv2(
                flashPool,
                // firstSwap.pool,
                flashBorrow,
                isBorrowToken0,
                swaps
            );
        } else if (flashProtocol == 1) {
            loanUniv3(
                flashPool,
                // firstSwap.pool,
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
        uint256 amountBorrow,
        bool isToken0Out, // 是否借出的token0
        bytes[] memory path
    ) public {
        // 归还哪个token, 借0还1， 借1还0
        address repayToken;
        if (isToken0Out) {
            repayToken = IUniswapV2Pair(pool).token1();
        } else {
            repayToken = IUniswapV2Pair(pool).token0();
        }
        // 最后最少应该归还多少,剩下的就是利润
        uint256 repayAmount = 0;
        // 合约内计算amountIn
        if (repayAmount == 0) {
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool)
                .getReserves();
            if (isToken0Out) {
                // repay token1
                repayAmount = UniswapV2Library.getAmountIn(
                    amountBorrow,
                    reserve1,
                    reserve0
                );
            } else {
                // repay token0
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
            address(this),
            // 需要flash 的 out(borrow)作为swap的in
            abi.encode(pool, repayToken, amountBorrow, repayAmount, path)
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
        // address to,
        // uint256 amountRepay, // Univ3 callback有repay的数量
        uint256 amountBorrow,
        bool isToken0Out, // 是否借出的token0
        bytes[] memory path
    ) internal {
        // 归还哪个token, 借0还1， 借1还0
        address repayToken;
        if (isToken0Out) {
            repayToken = IUniswapV3PoolImmutables(pool).token1();
        } else {
            repayToken = IUniswapV3PoolImmutables(pool).token0();
        }
        uint256 amount0 = 0;
        uint256 amount1 = 0;
        if (isToken0Out) {
            amount0 = amountBorrow;
        } else {
            amount1 = amountBorrow;
        }
        tmpPoolAddr = pool;

        uint160 sqrtPriceLimit = !isToken0Out
            ? TickMath.MIN_SQRT_RATIO + 1
            : TickMath.MAX_SQRT_RATIO - 1;

        IUniswapV3PoolActions(pool).swap(
            address(this),
            !isToken0Out,
            -int256(amountBorrow),
            sqrtPriceLimit,
            abi.encode(pool, repayToken, path)
        );
    }

    function uniswapV3SwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external override {
        require(msg.sender == tmpPoolAddr, "who");
        if (data.length == 0) {
            if (amount0 > 0) {
                IERC20(IUniswapV3PoolImmutables(msg.sender).token0()).transfer(
                    msg.sender,
                    uint256(amount0)
                );
            }
            if (amount1 > 0) {
                IERC20(IUniswapV3PoolImmutables(msg.sender).token1()).transfer(
                    msg.sender,
                    uint256(amount1)
                );
            }
            return;
        }
        (address repayPool, address repayToken, bytes[] memory swaps) = abi
            .decode(data, (address, address, bytes[]));

        uint256 repayAmount = amount0 > 0 ? uint256(amount0) : uint256(amount1);
        uint256 borrowAmount = amount0 > 0
            ? uint256(-amount1)
            : uint256(-amount0);

        // 带上repayAmount重新encode
        swapsAndRepay(
            abi.encode(repayPool, repayToken, borrowAmount, repayAmount, swaps)
        );
    }

    // univ2 swap 逻辑
    function swap_univ2(
        address pool,
        uint256 amountIn, // 上一个池子的amountOut就是这里的amountIn
        bool isToken0Out
    ) public returns (uint256) {
        uint256 out = 0;
        // 合约内计算amountIn
        if (out == 0) {
            (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool)
                .getReserves();
            if (isToken0Out) {
                // repay token1
                out = UniswapV2Library.getAmountOut(
                    amountIn,
                    reserve1,
                    reserve0
                );
            } else {
                // repay token0
                out = UniswapV2Library.getAmountOut(
                    amountIn,
                    reserve0,
                    reserve1
                );
            }
        }
        // 转入amountIn
        if (isToken0Out) {
            IERC20(IUniswapV2Pair(pool).token1()).transfer(pool, amountIn);
            IUniswapV2Pair(pool).swap(out, 0, address(this), "");
        } else {
            IERC20(IUniswapV2Pair(pool).token0()).transfer(pool, amountIn);
            IUniswapV2Pair(pool).swap(0, out, address(this), "");
        }
        return out;
    }

    // univ3 swap 逻辑, swap一定是知道amountIn的， 那么amountOut就会通过函数返回值拿到
    function swap_univ3(
        address pool,
        // address receiver,
        uint256 amountIn,
        bool isToken0Out // !zeroForOne
    ) internal returns (uint256) {
        uint160 sqrtPriceLimit = !isToken0Out
            ? TickMath.MIN_SQRT_RATIO + 1
            : TickMath.MAX_SQRT_RATIO - 1;

        tmpPoolAddr = pool;
        (int256 amount0, int256 amount1) = IUniswapV3PoolActions(pool).swap(
            address(this),
            !isToken0Out,
            int256(amountIn),
            sqrtPriceLimit,
            ""
        );
        return uint256(isToken0Out ? -amount0 : -amount1);
    }
}
