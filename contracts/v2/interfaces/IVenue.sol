// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IVenue {
    event Swapped(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    error ZeroAmount();
    error ZeroAddress();
    error NotVault(address caller);
    error UnsupportedPair(address tokenIn, address tokenOut);
    error InsufficientLiquidity(address token);
    error VenueSlippage(uint256 got, uint256 min);
    error StalePrice(address token, uint256 updatedAt);

    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut);

    function quoteExactIn(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);

    function isSupported(address token) external view returns (bool);

    function usdg() external view returns (address);
}
