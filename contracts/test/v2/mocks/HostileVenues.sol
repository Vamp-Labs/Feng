// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVenue} from "../../../v2/interfaces/IVenue.sol";

contract HostileVenue is IVenue {
    address public immutable override usdg;
    mapping(address => bool) public supported;
    mapping(address => uint256) public buyRate;
    mapping(address => uint256) public sellRate;
    uint256 public lieExtra;
    uint256 public shortBps;
    address public reenterTarget;
    bytes public reenterPayload;
    bool public reenterOk;
    bool public reenterTried;

    constructor(address usdg_) {
        usdg = usdg_;
    }

    function configure(address token, uint256 tokensPerUsdgUnit, uint256 usdgUnitsPer1e18Tokens) external {
        supported[token] = true;
        buyRate[token] = tokensPerUsdgUnit;
        sellRate[token] = usdgUnitsPer1e18Tokens;
    }

    function setLie(uint256 extra) external {
        lieExtra = extra;
    }

    function setShortBps(uint256 bps) external {
        shortBps = bps;
    }

    function setReenter(address target, bytes calldata payload) external {
        reenterTarget = target;
        reenterPayload = payload;
    }

    function isSupported(address token) external view returns (bool) {
        return supported[token];
    }

    function quoteExactIn(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        if (tokenIn == usdg) return amountIn * buyRate[tokenOut];
        return (amountIn * sellRate[tokenIn]) / 1e18;
    }

    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256)
    {
        if (reenterTarget != address(0)) {
            reenterTried = true;
            (reenterOk,) = reenterTarget.call(reenterPayload);
        }
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 out = quoteExactIn(tokenIn, tokenOut, amountIn);
        uint256 delivered = out - (out * shortBps) / 10_000;
        if (delivered < minAmountOut && shortBps == 0) revert VenueSlippage(delivered, minAmountOut);
        IERC20(tokenOut).transfer(recipient, delivered);
        return delivered + lieExtra;
    }
}
