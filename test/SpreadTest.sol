// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../src/Spread.sol";
import "../src/interfaces/IERC20.sol";
import "../lib/forge-std/src/Test.sol";
import "./TestSpreadCommon.sol";

import "../src/interfaces/IUniswapV3PoolActions.sol";
import "../src/interfaces/IUniswapV3SwapCallback.sol";

contract SpreadTest is TestSpreadCommon, IUniswapV3SwapCallback {
    // 模拟套利， 目标是赚取WETH， 分成买卖两种逻辑测试
    address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address link = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
    address usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address link_weth_v3 = 0x468b88941e7Cc0B88c1869d68ab6b570bCEF62Ff;
    address link_usdc_v3 = 0xDD092f5Dce127961AF6ebE975978c084C935Bcc8;
    address weth_usdc_v3 = 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;

    // 买逻辑：
    // 首先目标交易 WETH -> LINK,买上去
    // 则我们构造一个从该池借入WETH， 还入LINK的 flash (卖LINK)
    // swaps： WETH -> USDC -> LINK -> 还入
    // 最后检查WETH余额是否变多
    function testBuy() public {
        writeTokenBalance(address(this), address(weth), 1000 ether);
        writeTokenBalance(address(spread), address(weth), 100 ether);
        // 买LINK， 创造套利机会
        // vm.prank(address(spread));
        IUniswapV3PoolActions(link_weth_v3).swap(
            address(this),
            true,
            100 ether,
            4295128740,
            ""
        );
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encode(
            uint8(1),
            0xDD092f5Dce127961AF6ebE975978c084C935Bcc8,
            false
        );
        data[1] = abi.encode(
            uint8(1),
            0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443,
            true
        );
        vm.prank(address(spread));
        uint before = IERC20(weth).balanceOf(address(spread));
        emit log_uint(before);
        spread.startSpread(link_weth_v3, 1, 0.1 ether, false, data);
        uint afterx = IERC20(weth).balanceOf(address(spread));
        emit log_uint(afterx);
    }

    // 模拟套利， 目标是赚取WETH， 分成买卖两种逻辑测试
    address xai = 0x4Cb9a7AE498CEDcBb5EAe9f25736aE7d428C9D66;
    address xai_weth_v2 = 0xA43fe16908251ee70EF74718545e4FE6C5cCEc9f;
    address pepe_usdc_v3 = 0x261D53F3CD0B38DAbBAB252DCc8adEAA8C67bCbA;
    address weth_usdc_v3 = 0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;

    function uniswapV3SwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external override {
        if (data.length == 0) {
            if (amount0 > 0) {
                emit log_address(IUniswapV3PoolImmutables(msg.sender).token0());
                emit log_uint(
                    IERC20(IUniswapV3PoolImmutables(msg.sender).token0())
                        .balanceOf(address(this))
                );
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
        }
    }

}
