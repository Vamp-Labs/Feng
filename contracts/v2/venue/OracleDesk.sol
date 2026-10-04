// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPriceOracle} from "../../interfaces/IPriceOracle.sol";
import {IMintableStockToken} from "../../interfaces/IMintableStockToken.sol";
import {IOracleDesk, IRegistryGate} from "../interfaces/IOracleDesk.sol";

contract OracleDesk is IOracleDesk, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event MaxSwapSet(uint256 maxSwapUsdg);

    error SwapTooLarge(uint256 usdgAmount, uint256 maxSwapUsdg);

    uint256 private constant BPS = 10_000;
    uint16 public constant MAX_SPREAD_BPS = 100;

    address public immutable usdg;
    address public immutable oracle;
    address public immutable registry;
    uint256 public immutable maxPriceStaleness;
    uint8 private immutable _usdgDecimals;

    uint16 public spreadBps;
    uint256 public maxSwapUsdg;
    uint256 private _fundedUsdg;
    uint256 private _withdrawnUsdg;
    uint256 private _buyUsdgIn;
    uint256 private _sellUsdgOut;

    mapping(address => Mode) public mode;
    mapping(address => uint8) public tokenDecimals;

    constructor(
        address owner_,
        address usdg_,
        address oracle_,
        address registry_,
        uint16 spreadBps_,
        uint256 maxPriceStaleness_
    ) Ownable(owner_) {
        if (usdg_ == address(0) || oracle_ == address(0) || registry_ == address(0)) {
            revert ZeroAddress();
        }
        if (spreadBps_ > MAX_SPREAD_BPS) revert SpreadTooHigh(spreadBps_);
        uint8 usdgDec = IERC20Metadata(usdg_).decimals();
        if (usdgDec > 18) revert DecimalsTooHigh(usdg_, usdgDec);
        usdg = usdg_;
        oracle = oracle_;
        registry = registry_;
        maxPriceStaleness = maxPriceStaleness_;
        _usdgDecimals = usdgDec;
        spreadBps = spreadBps_;
        emit SpreadSet(spreadBps_);
    }

    function owner() public view override(IOracleDesk, Ownable) returns (address) {
        return Ownable.owner();
    }

    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (!IRegistryGate(registry).isRegistered(msg.sender)) revert NotVault(msg.sender);
        if (amountIn == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        (address token, bool buy) = _pair(tokenIn, tokenOut);
        (uint256 price, uint256 unit) = _price(token, buy);
        uint256 received;

        if (buy) {
            received = _pull(usdg, msg.sender, amountIn);
            amountOut = Math.mulDiv(received, unit, price);
            _checkOut(amountOut, minAmountOut);
            _checkCap(received);
            _buyUsdgIn += received;
            if (mode[token] == Mode.Mint) {
                IMintableStockToken(token).mint(recipient, amountOut);
            } else {
                if (IERC20(token).balanceOf(address(this)) < amountOut) revert InsufficientLiquidity(token);
                IERC20(token).safeTransfer(recipient, amountOut);
            }
        } else {
            received = _pull(token, msg.sender, amountIn);
            amountOut = Math.mulDiv(received, price, unit);
            _checkOut(amountOut, minAmountOut);
            _checkCap(amountOut);
            if (IERC20(usdg).balanceOf(address(this)) < amountOut) revert InsufficientLiquidity(usdg);
            if (mode[token] == Mode.Mint) IMintableStockToken(token).burn(address(this), received);
            _sellUsdgOut += amountOut;
            IERC20(usdg).safeTransfer(recipient, amountOut);
        }

        emit Swapped(msg.sender, tokenIn, tokenOut, received, amountOut, recipient);
    }

    function quoteExactIn(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        (address token, bool buy) = _pair(tokenIn, tokenOut);
        (uint256 price, uint256 unit) = _price(token, buy);
        amountOut = buy ? Math.mulDiv(amountIn, unit, price) : Math.mulDiv(amountIn, price, unit);
        if (amountOut == 0) revert ZeroAmount();
        _checkCap(buy ? amountIn : amountOut);
    }

    function isSupported(address token) external view returns (bool) {
        return token != usdg && mode[token] != Mode.Unsupported;
    }

    function setToken(address token, Mode mode_) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (token == usdg) revert UnsupportedPair(token, usdg);
        uint8 dec = tokenDecimals[token];
        if (mode_ == Mode.Unsupported) {
            if (mode[token] == Mode.Unsupported) revert NotConfigured(token);
        } else {
            dec = IERC20Metadata(token).decimals();
            if (dec > 18) revert DecimalsTooHigh(token, dec);
            tokenDecimals[token] = dec;
        }
        mode[token] = mode_;
        emit TokenConfigured(token, mode_, dec);
    }

    function setSpreadBps(uint16 spreadBps_) external onlyOwner {
        if (spreadBps_ > MAX_SPREAD_BPS) revert SpreadTooHigh(spreadBps_);
        spreadBps = spreadBps_;
        emit SpreadSet(spreadBps_);
    }

    function setMaxSwapUsdg(uint256 maxSwapUsdg_) external onlyOwner {
        maxSwapUsdg = maxSwapUsdg_;
        emit MaxSwapSet(maxSwapUsdg_);
    }

    function fundReserve(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 received = _pull(usdg, msg.sender, amount);
        _fundedUsdg += received;
        emit ReserveFunded(msg.sender, received);
    }

    function withdrawReserve(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (IERC20(usdg).balanceOf(address(this)) < amount) revert InsufficientLiquidity(usdg);
        _withdrawnUsdg += amount;
        IERC20(usdg).safeTransfer(to, amount);
        emit ReserveWithdrawn(to, amount);
    }

    function fundInventory(address token, uint256 amount) external onlyOwner nonReentrant {
        if (mode[token] == Mode.Unsupported) revert NotConfigured(token);
        if (amount == 0) revert ZeroAmount();
        uint256 received = _pull(token, msg.sender, amount);
        emit InventoryFunded(token, msg.sender, received);
    }

    function withdrawInventory(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == usdg || token == address(0)) revert NotConfigured(token);
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (IERC20(token).balanceOf(address(this)) < amount) revert InsufficientLiquidity(token);
        IERC20(token).safeTransfer(to, amount);
        emit InventoryWithdrawn(token, to, amount);
    }

    function reserveUsdg() external view returns (uint256) {
        return IERC20(usdg).balanceOf(address(this));
    }

    function tokenInventory(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function accounting()
        external
        view
        returns (uint256 fundedUsdg, uint256 withdrawnUsdg, uint256 buyUsdgIn, uint256 sellUsdgOut)
    {
        return (_fundedUsdg, _withdrawnUsdg, _buyUsdgIn, _sellUsdgOut);
    }

    function _pair(address tokenIn, address tokenOut) private view returns (address token, bool buy) {
        if (tokenIn == usdg && tokenOut != usdg) {
            token = tokenOut;
            buy = true;
        } else if (tokenOut == usdg && tokenIn != usdg) {
            token = tokenIn;
        } else {
            revert UnsupportedPair(tokenIn, tokenOut);
        }
        if (mode[token] == Mode.Unsupported) revert UnsupportedPair(tokenIn, tokenOut);
    }

    function _price(address token, bool buy) private view returns (uint256 price, uint256 unit) {
        (uint256 p, uint256 updatedAt) = IPriceOracle(oracle).getPrice(token);
        if (block.timestamp - updatedAt > maxPriceStaleness) revert StalePrice(token, updatedAt);
        uint256 spread = spreadBps;
        price = buy
            ? Math.mulDiv(p, BPS + spread, BPS, Math.Rounding.Ceil)
            : Math.mulDiv(p, BPS - spread, BPS, Math.Rounding.Floor);
        unit = 10 ** (uint256(tokenDecimals[token]) + 18 - _usdgDecimals);
    }

    function _pull(address token, address from, uint256 amount) private returns (uint256 received) {
        uint256 before = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(from, address(this), amount);
        received = IERC20(token).balanceOf(address(this)) - before;
    }

    function _checkCap(uint256 usdgAmount) private view {
        uint256 cap = maxSwapUsdg;
        if (cap != 0 && usdgAmount > cap) revert SwapTooLarge(usdgAmount, cap);
    }

    function _checkOut(uint256 amountOut, uint256 minAmountOut) private pure {
        if (amountOut == 0) revert ZeroAmount();
        if (amountOut < minAmountOut) revert VenueSlippage(amountOut, minAmountOut);
    }
}
