// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Constituent} from "../interfaces/IStrategyVault.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IVenue} from "./interfaces/IVenue.sol";
import {IStrategyTokenV2} from "./interfaces/IStrategyTokenV2.sol";
import {IStrategyVaultV2, VaultParams} from "./interfaces/IStrategyVaultV2.sol";
import {StrategyTokenV2} from "./StrategyTokenV2.sol";

contract StrategyVaultV2 is IStrategyVaultV2, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    struct Slot {
        address token;
        uint16 targetWeightBps;
        bool isStrategyToken;
        uint8 decimals;
    }

    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_CONSTITUENTS = 6;
    uint16 private constant MAX_SLIPPAGE_BPS = 500;
    uint256 private constant LEG_TOLERANCE_BPS = 10;
    uint256 private constant THRESHOLD_BAND_BPS = 10;
    uint256 private constant CHECKPOINT_MIN_INTERVAL = 30 minutes;
    uint256 private constant VIRTUAL_ASSETS = 1;

    address public immutable token;
    address public immutable usdgToken;
    uint8 public immutable usdgDecimals;
    address public immutable priceOracle;
    address public immutable venue;
    address public immutable guardian;
    uint16 public immutable maxWeightBps;
    uint16 public immutable maxSlippageBps;
    uint256 public immutable rebalanceInterval;
    uint8 private immutable strategyDepth;
    uint256 public immutable maxPriceStaleness;
    uint256 public immutable VIRTUAL_SHARES;
    uint256 public immutable MIN_LEG_USDG;

    uint64 private _lastRebalanceTimestamp;
    uint64 private _lastCheckpointTimestamp;

    Slot[] private _slots;

    constructor(VaultParams memory p) {
        if (p.usdg == address(0) || p.oracle == address(0) || p.venue == address(0) || p.guardian == address(0)) {
            revert ZeroAddress();
        }
        uint256 n = p.constituents.length;
        if (n == 0) revert EmptyConstituents();
        if (n > MAX_CONSTITUENTS) revert TooManyConstituents();
        if (p.maxSlippageBps == 0 || p.maxSlippageBps > MAX_SLIPPAGE_BPS) revert InvalidMaxSlippage(p.maxSlippageBps);

        uint8 d = IERC20Metadata(p.usdg).decimals();
        if (d > 18) revert UnsupportedDecimals(p.usdg, d);

        uint256 weightSum;
        for (uint256 i = 0; i < n; i++) {
            Constituent memory c = p.constituents[i];
            if (c.token == address(0)) revert ZeroAddress();
            if (c.token == p.usdg) revert ConstituentIsUsdg();
            uint8 dec = IERC20Metadata(c.token).decimals();
            if (dec > 18) revert UnsupportedDecimals(c.token, dec);
            weightSum += c.targetWeightBps;
            _slots.push(Slot(c.token, c.targetWeightBps, c.isStrategyToken, dec));
        }
        if (weightSum != BPS) revert WeightsMustSumTo10000();

        usdgToken = p.usdg;
        usdgDecimals = d;
        priceOracle = p.oracle;
        venue = p.venue;
        guardian = p.guardian;
        maxWeightBps = p.maxWeightBps;
        maxSlippageBps = p.maxSlippageBps;
        rebalanceInterval = p.rebalanceInterval;
        strategyDepth = p.depth;
        maxPriceStaleness = p.maxPriceStaleness;
        VIRTUAL_SHARES = uint256(10) ** (d >= 6 ? 12 : 18 - d);
        uint256 unit = uint256(10) ** d;
        MIN_LEG_USDG = Math.max(unit / 100, 1);
        _lastRebalanceTimestamp = uint64(block.timestamp);

        token = address(new StrategyTokenV2(p.name, p.symbol, address(this)));
    }

    function deposit(uint256 usdgAmount, address receiver, uint256 minShares)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        _checkIO(usdgAmount, receiver);
        Slot[] memory cs = _slots;
        _checkAllFresh(cs);

        (, uint256 nb) = _values(cs, true);
        uint256 received = _pull(usdgToken, usdgAmount);
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 slice = (received * cs[i].targetWeightBps) / BPS;
            if (slice >= MIN_LEG_USDG) _buy(cs[i], slice);
        }
        (, uint256 na) = _values(cs, false);
        if (na <= nb) revert NoValueAdded();

        shares = _issue(na - nb, nb, receiver, minShares);
        emit Deposit(msg.sender, receiver, received, shares);
        _checkpoint(na);
    }

    function depositInKind(address token_, uint256 amount, address receiver, uint256 minShares)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        _checkIO(amount, receiver);
        Slot[] memory cs = _slots;
        Slot memory s = cs[_indexOf(cs, token_)];
        _checkAllFresh(cs);

        (, uint256 nb) = _values(cs, true);
        uint256 got = _pull(token_, amount);
        uint256 valueAdded = _valueOf(s, got, false);
        if (valueAdded == 0) revert NoValueAdded();

        (, uint256 na) = _values(cs, false);
        _guardWeight(s, na);

        shares = _issue(valueAdded, nb, receiver, minShares);
        emit DepositInKind(msg.sender, receiver, token_, got, valueAdded, shares);
        _checkpoint(na);
    }

    function redeem(uint256 shares, address receiver, address owner, uint256 minUsdgOut)
        external
        nonReentrant
        returns (uint256 usdgOut)
    {
        _checkIO(shares, receiver);
        Slot[] memory cs = _slots;
        _checkAllFresh(cs);

        uint256 supply = _supply();
        _burnShares(owner, shares);

        usdgOut = Math.mulDiv(_bal(usdgToken), shares, supply);
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 part = Math.mulDiv(_bal(cs[i].token), shares, supply);
            if (part != 0) usdgOut += _sell(cs[i], part);
        }
        if (usdgOut == 0) revert ZeroAssets();
        _atLeast(usdgOut, minUsdgOut);

        IERC20(usdgToken).safeTransfer(receiver, usdgOut);
        emit Redeem(msg.sender, receiver, owner, shares, usdgOut);
        (, uint256 na) = _values(cs, false);
        _checkpoint(na);
    }

    function redeemInKind(uint256 shares, address receiver, address owner)
        external
        nonReentrant
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        return _redeemInKind(shares, receiver, owner, 0);
    }

    function redeemInKindExcluding(uint256 shares, address receiver, address owner, uint256 skipMask)
        external
        nonReentrant
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        return _redeemInKind(shares, receiver, owner, skipMask);
    }

    function previewDeposit(uint256 usdgAmount) external view nonReentrantView returns (uint256 shares) {
        Slot[] memory cs = _slots;
        uint256 valueAdded = usdgAmount;
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 slice = (usdgAmount * cs[i].targetWeightBps) / BPS;
            if (slice < MIN_LEG_USDG) continue;
            valueAdded -= slice;
            if (cs[i].isStrategyToken) {
                IStrategyVaultV2 child = _child(cs[i]);
                valueAdded += child.previewRedeem(child.previewDeposit(slice));
            } else {
                uint256 out = IVenue(venue).quoteExactIn(usdgToken, cs[i].token, slice);
                valueAdded += _valueOf(cs[i], out, false);
            }
        }
        (, uint256 nb) = _values(cs, true);
        return _sharesFor(valueAdded, nb);
    }

    function previewDepositInKind(address token_, uint256 amount) external view nonReentrantView returns (uint256) {
        Slot[] memory cs = _slots;
        uint256 valueAdded = _valueOf(cs[_indexOf(cs, token_)], amount, false);
        (, uint256 nb) = _values(cs, true);
        return _sharesFor(valueAdded, nb);
    }

    function previewRedeem(uint256 shares) external view nonReentrantView returns (uint256) {
        uint256 supply = _supply();
        if (supply == 0) return 0;
        (, uint256 total) = _values(_slots, false);
        return Math.mulDiv(shares, total, supply);
    }

    function totalAssetsUSDG() external view nonReentrantView returns (uint256 total) {
        (, total) = _values(_slots, false);
    }

    function sharePrice() external view nonReentrantView returns (uint256) {
        (, uint256 total) = _values(_slots, false);
        return _sharePriceOf(total, _supply());
    }

    function inceptionSharePrice() public view returns (uint256) {
        return Math.mulDiv(1e18, VIRTUAL_ASSETS, VIRTUAL_SHARES);
    }

    function weights() external view nonReentrantView returns (uint16[] memory currentBps) {
        Slot[] memory cs = _slots;
        (uint256[] memory cur, uint256 total) = _values(cs, false);
        currentBps = new uint16[](cs.length);
        if (total == 0) return currentBps;
        for (uint256 i = 0; i < cs.length; i++) {
            currentBps[i] = uint16((cur[i] * BPS) / total);
        }
    }

    function effectiveMaxWeightBps(uint256 index) external view returns (uint16) {
        return _effectiveMax(_slots[index].targetWeightBps);
    }

    function priceStatus() external view returns (bool fresh, uint256 oldestUpdatedAt) {
        Slot[] memory cs = _slots;
        oldestUpdatedAt = type(uint256).max;
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 updatedAt;
            if (cs[i].isStrategyToken) {
                bool childFresh;
                try _child(cs[i]).priceStatus() returns (bool f, uint256 u) {
                    childFresh = f;
                    updatedAt = u;
                } catch {
                    return (false, 0);
                }
                if (!childFresh) return (false, updatedAt);
            } else {
                try IPriceOracle(priceOracle).getPrice(cs[i].token) returns (uint256, uint256 u) {
                    updatedAt = u;
                } catch {
                    return (false, 0);
                }
            }
            if (updatedAt < oldestUpdatedAt) oldestUpdatedAt = updatedAt;
        }
        fresh = oldestUpdatedAt + maxPriceStaleness >= block.timestamp;
    }

    function getConstituents() external view returns (Constituent[] memory result) {
        Slot[] memory cs = _slots;
        result = new Constituent[](cs.length);
        for (uint256 i = 0; i < cs.length; i++) {
            result[i] = Constituent(cs[i].token, cs[i].targetWeightBps, cs[i].isStrategyToken);
        }
    }

    function depth() external view returns (uint8) {
        return strategyDepth;
    }

    function rebalanceNeeded() external view nonReentrantView returns (bool timeBased, bool thresholdBased) {
        if (paused()) return (false, false);
        Slot[] memory cs = _slots;
        (uint256[] memory cur, uint256 total) = _values(cs, false);
        return _flags(cs, cur, total, _supply());
    }

    function executeRebalance() external nonReentrant whenNotPaused {
        Slot[] memory cs = _slots;
        uint256 supply = _supply();
        (uint256[] memory cur, uint256 total) = _values(cs, false);
        (bool timeBased, bool thresholdBased) = _flags(cs, cur, total, supply);
        if (!timeBased && !thresholdBased) revert RebalanceNotNeeded();
        _checkAllFresh(cs);

        uint256 tol = _tolerance(total);
        _sellPass(cs, cur, total, tol);
        _buyPass(cs, cur, total, tol);

        _lastRebalanceTimestamp = uint64(block.timestamp);
        (, uint256 na) = _values(cs, false);
        _checkpoint(na);
        emit Rebalanced(block.timestamp, timeBased, thresholdBased, _sharePriceOf(na, supply));
    }

    function checkpoint() external nonReentrant {
        uint256 next = uint256(_lastCheckpointTimestamp) + CHECKPOINT_MIN_INTERVAL;
        if (block.timestamp < next) revert CheckpointTooSoon(next);
        Slot[] memory cs = _slots;
        _checkAllFresh(cs);
        (, uint256 total) = _values(cs, false);
        _checkpoint(total);
    }

    function pause() external {
        if (msg.sender != guardian) revert NotGuardian();
        _pause();
    }

    function unpause() external {
        if (msg.sender != guardian) revert NotGuardian();
        _unpause();
    }

    function paused() public view override(IStrategyVaultV2, Pausable) returns (bool) {
        return super.paused();
    }

    function lastRebalanceTimestamp() external view returns (uint256) {
        return _lastRebalanceTimestamp;
    }

    function lastCheckpointTimestamp() external view returns (uint256) {
        return _lastCheckpointTimestamp;
    }

    function _guardWeight(Slot memory s, uint256 total) private view {
        if ((_valueOf(s, _bal(s.token), false) * BPS) / total > _effectiveMax(s.targetWeightBps)) {
            revert ExceedsMaxWeight(s.token);
        }
    }

    function _redeemInKind(uint256 shares, address receiver, address owner, uint256 skipMask)
        private
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        _checkIO(shares, receiver);
        Slot[] memory cs = _slots;
        if (skipMask >> (cs.length + 1) != 0) revert InvalidSkipMask();

        uint256 supply = _supply();
        _burnShares(owner, shares);
        uint256 n = cs.length;
        tokens = new address[](n + 1);
        amounts = new uint256[](n + 1);
        tokens[n] = usdgToken;
        for (uint256 i = 0; i <= n; i++) {
            if (i < n) tokens[i] = cs[i].token;
            if ((skipMask >> i) & 1 == 1) continue;
            amounts[i] = Math.mulDiv(_bal(tokens[i]), shares, supply);
            if (amounts[i] != 0) IERC20(tokens[i]).safeTransfer(receiver, amounts[i]);
        }
        emit RedeemInKind(msg.sender, receiver, owner, shares);
    }

    function _sellPass(Slot[] memory cs, uint256[] memory cur, uint256 total, uint256 tol) private {
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 target = (total * cs[i].targetWeightBps) / BPS;
            if (cur[i] <= target + tol) continue;
            uint256 excess = cur[i] - target;
            uint256 bal = _bal(cs[i].token);
            uint256 amount = cs[i].isStrategyToken
                ? (bal * excess) / cur[i]
                : Math.min(bal, Math.mulDiv(excess, _scale(cs[i].decimals), _price(cs[i].token)));
            if (amount != 0) _sell(cs[i], amount);
        }
    }

    function _buyPass(Slot[] memory cs, uint256[] memory cur, uint256 total, uint256 tol) private {
        uint256 n = cs.length;
        uint256[] memory deficit = new uint256[](n);
        uint256 totalDeficit;
        for (uint256 i = 0; i < n; i++) {
            uint256 target = (total * cs[i].targetWeightBps) / BPS;
            if (cur[i] + tol < target) {
                deficit[i] = target - cur[i];
                totalDeficit += deficit[i];
            }
        }
        if (totalDeficit == 0) return;
        uint256 budget = _bal(usdgToken);
        for (uint256 i = 0; i < n; i++) {
            if (deficit[i] == 0) continue;
            uint256 spend = budget >= totalDeficit ? deficit[i] : (deficit[i] * budget) / totalDeficit;
            if (spend >= MIN_LEG_USDG) _buy(cs[i], spend);
        }
    }

    function _buy(Slot memory s, uint256 spend) private {
        uint256 before = _bal(s.token);
        uint256 minOut;
        if (s.isStrategyToken) {
            IStrategyVaultV2 child = _childAt(s.token);
            minOut = _minOut(child.previewDeposit(spend));
            IERC20(usdgToken).forceApprove(address(child), spend);
            child.deposit(spend, address(this), minOut);
            IERC20(usdgToken).forceApprove(address(child), 0);
        } else {
            minOut = _minOut(_tokensFor(s, spend));
            _swap(usdgToken, s.token, spend, minOut);
        }
        uint256 got = _bal(s.token) - before;
        _atLeast(got, minOut);
        emit LegTraded(s.token, true, spend, got);
    }

    function _sell(Slot memory s, uint256 amount) private returns (uint256 got) {
        uint256 expected = _valueOf(s, amount, false);
        if (expected == 0) return 0;
        uint256 minOut = _minOut(expected);
        uint256 before = _bal(usdgToken);
        if (s.isStrategyToken) {
            _redeemChild(s.token, amount, minOut);
        } else {
            _swap(s.token, usdgToken, amount, minOut);
        }
        got = _bal(usdgToken) - before;
        _atLeast(got, minOut);
        emit LegTraded(s.token, false, got, amount);
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut) private {
        IERC20(tokenIn).forceApprove(venue, amountIn);
        IVenue(venue).swapExactIn(tokenIn, tokenOut, amountIn, minOut, address(this));
        IERC20(tokenIn).forceApprove(venue, 0);
    }

    function _redeemChild(address childToken, uint256 shares, uint256 minOut) private {
        try _childAt(childToken).redeem(shares, address(this), address(this), minOut) {}
        catch (bytes memory reason) {
            revert ChildRedeemFailed(childToken, reason);
        }
    }

    function _checkIO(uint256 amount, address receiver) private pure {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();
    }

    function _atLeast(uint256 got, uint256 min) private pure {
        if (got < min) revert SlippageExceeded(got, min);
    }

    function _issue(uint256 valueAdded, uint256 navBefore, address receiver, uint256 minShares)
        private
        returns (uint256 shares)
    {
        if (valueAdded == 0) revert NoValueAdded();
        shares = _sharesFor(valueAdded, navBefore);
        if (shares == 0) revert ZeroShares();
        _atLeast(shares, minShares);
        StrategyTokenV2(token).mint(receiver, shares);
    }

    function _sharesFor(uint256 valueAdded, uint256 navCeil) private view returns (uint256) {
        return Math.mulDiv(valueAdded, _supply() + VIRTUAL_SHARES, navCeil + VIRTUAL_ASSETS);
    }

    function _sharePriceOf(uint256 total, uint256 supply) private view returns (uint256) {
        return supply == 0 ? inceptionSharePrice() : Math.mulDiv(total, 1e18, supply);
    }

    function _burnShares(address owner, uint256 shares) private {
        if (msg.sender == owner) {
            StrategyTokenV2(token).burn(owner, shares);
        } else {
            StrategyTokenV2(token).burnFrom(owner, msg.sender, shares);
        }
    }

    function _pull(address asset, uint256 amount) private returns (uint256 got) {
        uint256 before = _bal(asset);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        got = _bal(asset) - before;
    }

    function _checkpoint(uint256 total) private {
        _lastCheckpointTimestamp = uint64(block.timestamp);
        emit NavCheckpoint(block.timestamp, total, _supply());
    }

    function _checkAllFresh(Slot[] memory cs) private view {
        for (uint256 i = 0; i < cs.length; i++) {
            if (cs[i].isStrategyToken) {
                (bool fresh, uint256 oldest) = _child(cs[i]).priceStatus();
                if (!fresh) revert StalePrice(cs[i].token, oldest);
            } else {
                (, uint256 updatedAt) = _priceAt(cs[i].token);
                if (updatedAt + maxPriceStaleness < block.timestamp) revert StalePrice(cs[i].token, updatedAt);
            }
        }
    }

    function _flags(Slot[] memory cs, uint256[] memory cur, uint256 total, uint256 supply)
        private
        view
        returns (bool timeBased, bool thresholdBased)
    {
        timeBased = supply > 0 && block.timestamp >= uint256(_lastRebalanceTimestamp) + rebalanceInterval;
        if (total == 0 || supply == 0) return (timeBased, false);
        uint256 tol = _tolerance(total);
        for (uint256 i = 0; i < cs.length; i++) {
            if (
                (cur[i] * BPS) / total > _effectiveMax(cs[i].targetWeightBps)
                    && cur[i] > (total * cs[i].targetWeightBps) / BPS + tol
            ) {
                return (timeBased, true);
            }
        }
    }

    function _tolerance(uint256 total) private view returns (uint256) {
        return Math.max((total * LEG_TOLERANCE_BPS) / BPS, MIN_LEG_USDG);
    }

    function _effectiveMax(uint16 target) private view returns (uint16) {
        return uint16(Math.min(BPS, Math.max(maxWeightBps, uint256(target) + THRESHOLD_BAND_BPS)));
    }

    function _values(Slot[] memory cs, bool up) private view returns (uint256[] memory cur, uint256 total) {
        cur = new uint256[](cs.length);
        total = _bal(usdgToken);
        for (uint256 i = 0; i < cs.length; i++) {
            cur[i] = _valueOf(cs[i], _bal(cs[i].token), up);
            total += cur[i];
        }
    }

    function _valueOf(Slot memory s, uint256 amount, bool up) private view returns (uint256 v) {
        if (amount == 0) return 0;
        if (s.isStrategyToken) {
            v = _child(s).previewRedeem(amount);
            if (up) v += 1;
        } else {
            v = Math.mulDiv(amount, _price(s.token), _scale(s.decimals), up ? Math.Rounding.Ceil : Math.Rounding.Floor);
        }
    }

    function _tokensFor(Slot memory s, uint256 value) private view returns (uint256) {
        return Math.mulDiv(value, _scale(s.decimals), _price(s.token));
    }

    function _scale(uint8 dec) private view returns (uint256) {
        return uint256(10) ** (uint256(dec) + 18 - usdgDecimals);
    }

    function _bal(address asset) private view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function _supply() private view returns (uint256) {
        return IERC20(token).totalSupply();
    }

    function _minOut(uint256 value) private view returns (uint256) {
        return (value * (BPS - maxSlippageBps)) / BPS;
    }

    function _price(address asset) private view returns (uint256 price) {
        (price,) = _priceAt(asset);
    }

    function _priceAt(address asset) private view returns (uint256 price, uint256 updatedAt) {
        return IPriceOracle(priceOracle).getPrice(asset);
    }

    function _child(Slot memory s) private view returns (IStrategyVaultV2) {
        return _childAt(s.token);
    }

    function _childAt(address childToken) private view returns (IStrategyVaultV2) {
        return IStrategyVaultV2(IStrategyTokenV2(childToken).vault());
    }

    function _indexOf(Slot[] memory cs, address asset) private pure returns (uint256) {
        for (uint256 i = 0; i < cs.length; i++) {
            if (cs[i].token == asset) return i;
        }
        revert TokenNotConstituent(asset);
    }
}
