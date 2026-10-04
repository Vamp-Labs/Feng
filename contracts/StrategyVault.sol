// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {StrategyToken} from "./StrategyToken.sol";
import {Constituent, IStrategyVault} from "./interfaces/IStrategyVault.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IMintableStockToken} from "./interfaces/IMintableStockToken.sol";

contract StrategyVault is IStrategyVault, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint8 private constant DECIMALS_OFFSET = 3;

    StrategyToken public immutable token;
    IERC20 public immutable usdgToken;
    IPriceOracle public immutable priceOracle;
    uint16 public immutable maxWeightBps;
    uint256 public immutable rebalanceInterval;
    uint8 public immutable strategyDepth;
    uint256 public immutable maxPriceStaleness;

    uint256 public lastRebalanceTimestamp;

    Constituent[] private _constituents;

    error ZeroAmount();
    error ZeroAddress();
    error ZeroShares();
    error EmptyConstituents();
    error WeightsMustSumTo10000();
    error StalePrice(address token, uint256 updatedAt);
    error RebalanceNotNeeded();

    constructor(
        string memory name_,
        string memory symbol_,
        address usdgToken_,
        address priceOracle_,
        Constituent[] memory constituents_,
        uint16 maxWeightBps_,
        uint256 rebalanceInterval_,
        uint8 depth_,
        uint256 maxPriceStaleness_
    ) {
        require(usdgToken_ != address(0), "zero usdg");
        require(priceOracle_ != address(0), "zero oracle");
        if (constituents_.length == 0) revert EmptyConstituents();

        uint256 weightSum;
        for (uint256 i = 0; i < constituents_.length; i++) {
            require(constituents_[i].token != address(0), "zero constituent");
            weightSum += constituents_[i].targetWeightBps;
            _constituents.push(constituents_[i]);
        }
        if (weightSum != 10_000) revert WeightsMustSumTo10000();

        usdgToken = IERC20(usdgToken_);
        priceOracle = IPriceOracle(priceOracle_);
        maxWeightBps = maxWeightBps_;
        rebalanceInterval = rebalanceInterval_;
        strategyDepth = depth_;
        maxPriceStaleness = maxPriceStaleness_;
        lastRebalanceTimestamp = block.timestamp;

        token = new StrategyToken(name_, symbol_, address(this));
    }

    function deposit(uint256 usdgAmount, address receiver) external nonReentrant returns (uint256 shares) {
        if (usdgAmount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        _checkAllFresh();

        shares = _convertToShares(usdgAmount, Math.Rounding.Floor);
        if (shares == 0) revert ZeroShares();

        usdgToken.safeTransferFrom(msg.sender, address(this), usdgAmount);

        uint256 n = _constituents.length;
        for (uint256 i = 0; i < n; i++) {
            Constituent storage c = _constituents[i];
            uint256 slice = (usdgAmount * c.targetWeightBps) / 10_000;
            if (slice == 0) continue;

            if (c.isStrategyToken) {
                address childVault = StrategyToken(c.token).vault();
                usdgToken.forceApprove(childVault, slice);
                IStrategyVault(childVault).deposit(slice, address(this));
            } else {
                (uint256 price,) = priceOracle.getPrice(c.token);
                uint256 amount = (slice * 1e18) / price;
                IMintableStockToken(c.token).mint(address(this), amount);
            }
        }

        token.mint(receiver, shares);
        emit Deposit(msg.sender, receiver, usdgAmount, shares);
    }

    function redeem(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        returns (uint256 usdgAmount)
    {
        if (shares == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
        _checkAllFresh();

        uint256 supplyBefore = token.totalSupply();
        uint256 cashBalance = usdgToken.balanceOf(address(this));
        usdgAmount = (cashBalance * shares) / supplyBefore;

        if (msg.sender == owner) {
            token.burn(owner, shares);
        } else {
            IERC20(address(token)).safeTransferFrom(owner, address(this), shares);
            token.burn(address(this), shares);
        }

        uint256 n = _constituents.length;
        for (uint256 i = 0; i < n; i++) {
            Constituent storage c = _constituents[i];
            uint256 balance = IERC20(c.token).balanceOf(address(this));
            if (balance == 0) continue;
            uint256 unwind = (balance * shares) / supplyBefore;
            if (unwind == 0) continue;

            if (c.isStrategyToken) {
                IERC20(c.token).safeTransfer(receiver, unwind);
            } else {
                IMintableStockToken(c.token).burn(address(this), unwind);
            }
        }

        if (usdgAmount > 0) {
            usdgToken.safeTransfer(receiver, usdgAmount);
        }

        emit Redeem(msg.sender, receiver, owner, shares, usdgAmount);
    }

    function previewDeposit(uint256 usdgAmount) external view nonReentrantView returns (uint256) {
        return _convertToShares(usdgAmount, Math.Rounding.Floor);
    }

    function previewRedeem(uint256 shares) external view nonReentrantView returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function totalAssetsUSDG() external view nonReentrantView returns (uint256) {
        return _totalAssetsUSDG();
    }

    function getConstituents() external view returns (Constituent[] memory result) {
        uint256 n = _constituents.length;
        result = new Constituent[](n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = _constituents[i];
        }
    }

    function depth() external view returns (uint8) {
        return strategyDepth;
    }

    function rebalanceNeeded() external view nonReentrantView returns (bool timeBased, bool thresholdBased) {
        return _rebalanceNeeded();
    }

    function executeRebalance() external nonReentrant {
        (bool timeBased, bool thresholdBased) = _rebalanceNeeded();
        if (!timeBased && !thresholdBased) revert RebalanceNotNeeded();
        _checkAllFresh();

        uint256 total = _totalAssetsUSDG();
        uint256 n = _constituents.length;
        for (uint256 i = 0; i < n; i++) {
            _rebalanceConstituent(_constituents[i], total);
        }

        lastRebalanceTimestamp = block.timestamp;
        emit Rebalanced(block.timestamp, timeBased, thresholdBased);
    }

    function _rebalanceConstituent(Constituent storage c, uint256 total) private {
        uint256 targetValue = (total * c.targetWeightBps) / 10_000;
        uint256 currentValue = _constituentValueUSDG(c);

        if (c.isStrategyToken) {
            address childVault = StrategyToken(c.token).vault();
            if (currentValue > targetValue) {
                uint256 balance = IERC20(c.token).balanceOf(address(this));
                if (balance == 0) return;
                uint256 excessValue = currentValue - targetValue;
                uint256 sharesToRedeem = (balance * excessValue) / currentValue;
                if (sharesToRedeem == 0) return;
                IStrategyVault(childVault).redeem(sharesToRedeem, address(this), address(this));
            } else if (currentValue < targetValue) {
                uint256 deficitValue = targetValue - currentValue;
                uint256 available = usdgToken.balanceOf(address(this));
                uint256 toDeposit = deficitValue > available ? available : deficitValue;
                if (toDeposit == 0) return;
                usdgToken.forceApprove(childVault, toDeposit);
                IStrategyVault(childVault).deposit(toDeposit, address(this));
            }
        } else {
            (uint256 price,) = priceOracle.getPrice(c.token);
            if (currentValue > targetValue) {
                uint256 excessValue = currentValue - targetValue;
                uint256 burnAmount = (excessValue * 1e18) / price;
                uint256 balance = IERC20(c.token).balanceOf(address(this));
                if (burnAmount > balance) burnAmount = balance;
                if (burnAmount == 0) return;
                IMintableStockToken(c.token).burn(address(this), burnAmount);
            } else if (currentValue < targetValue) {
                uint256 deficitValue = targetValue - currentValue;
                uint256 mintAmount = (deficitValue * 1e18) / price;
                if (mintAmount == 0) return;
                IMintableStockToken(c.token).mint(address(this), mintAmount);
            }
        }
    }

    function _checkAllFresh() private view {
        uint256 n = _constituents.length;
        for (uint256 i = 0; i < n; i++) {
            Constituent storage c = _constituents[i];
            if (!c.isStrategyToken) {
                (, uint256 updatedAt) = priceOracle.getPrice(c.token);
                if (block.timestamp - updatedAt > maxPriceStaleness) {
                    revert StalePrice(c.token, updatedAt);
                }
            }
        }
    }

    function _rebalanceNeeded() private view returns (bool timeBased, bool thresholdBased) {
        timeBased = block.timestamp >= lastRebalanceTimestamp + rebalanceInterval;
        uint256 total = _totalAssetsUSDG();
        if (total == 0) return (timeBased, false);

        uint256 n = _constituents.length;
        for (uint256 i = 0; i < n; i++) {
            uint256 value = _constituentValueUSDG(_constituents[i]);
            uint256 weightBps = (value * 10_000) / total;
            if (weightBps > maxWeightBps) {
                thresholdBased = true;
                break;
            }
        }
    }

    function _totalAssetsUSDG() private view returns (uint256 total) {
        uint256 n = _constituents.length;
        for (uint256 i = 0; i < n; i++) {
            total += _constituentValueUSDG(_constituents[i]);
        }
    }

    function _constituentValueUSDG(Constituent storage c) private view returns (uint256) {
        uint256 balance = IERC20(c.token).balanceOf(address(this));
        if (balance == 0) return 0;

        if (c.isStrategyToken) {
            address childVault = StrategyToken(c.token).vault();
            return IStrategyVault(childVault).previewRedeem(balance);
        }

        (uint256 price,) = priceOracle.getPrice(c.token);
        return (balance * price) / 1e18;
    }

    function _convertToShares(uint256 usdgAmount, Math.Rounding rounding) private view returns (uint256) {
        return usdgAmount.mulDiv(token.totalSupply() + 10 ** DECIMALS_OFFSET, _totalAssetsUSDG() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) private view returns (uint256) {
        return shares.mulDiv(_totalAssetsUSDG() + 1, token.totalSupply() + 10 ** DECIMALS_OFFSET, rounding);
    }
}
