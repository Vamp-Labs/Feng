// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Constituent} from "../interfaces/IStrategyVault.sol";
import {IVenue} from "./interfaces/IVenue.sol";
import {IPriceOracleV2} from "./interfaces/IPriceOracleV2.sol";
import {IMarketplaceRegistryV2, StrategyMeta} from "./interfaces/IMarketplaceRegistryV2.sol";
import {IStrategyVaultV2, VaultParams} from "./interfaces/IStrategyVaultV2.sol";
import {IStrategyFactoryV2, IVaultDeployerV2} from "./interfaces/IStrategyFactoryV2.sol";

contract StrategyFactoryV2 is IStrategyFactoryV2 {
    uint8 public constant MAX_DEPTH = 2;
    uint8 public constant MAX_CONSTITUENTS = 6;
    uint16 public constant MIN_WEIGHT_BPS = 100;
    uint16 public constant MAX_SLIPPAGE_BPS = 500;
    uint256 public constant MIN_REBALANCE_INTERVAL = 1 hours;
    uint256 public constant MAX_REBALANCE_INTERVAL = 365 days;

    address public immutable registry;
    address public immutable priceOracle;
    address public immutable venue;
    address public immutable usdg;
    uint8 public immutable usdgDecimals;
    address public immutable guardian;
    address public immutable vaultDeployer;
    uint256 public immutable maxPriceStaleness;

    mapping(address => address) public vaultOf;

    constructor(
        address registry_,
        address priceOracle_,
        address venue_,
        address usdg_,
        address guardian_,
        address vaultDeployer_,
        uint256 maxPriceStaleness_
    ) {
        if (
            registry_ == address(0) || priceOracle_ == address(0) || venue_ == address(0) || usdg_ == address(0)
                || guardian_ == address(0) || vaultDeployer_ == address(0) || maxPriceStaleness_ == 0
        ) revert ZeroAddress();
        uint8 d = IERC20Metadata(usdg_).decimals();
        if (d > 18) revert UnsupportedUsdgDecimals(d);
        if (IVenue(venue_).usdg() != usdg_) revert VenueUsdgMismatch();
        registry = registry_;
        priceOracle = priceOracle_;
        venue = venue_;
        usdg = usdg_;
        usdgDecimals = d;
        guardian = guardian_;
        vaultDeployer = vaultDeployer_;
        maxPriceStaleness = maxPriceStaleness_;
    }

    function createStrategy(
        string calldata name,
        string calldata symbol,
        Constituent[] calldata constituents,
        uint16 maxWeightBps,
        uint256 rebalanceInterval,
        uint16 maxSlippageBps,
        StrategyMeta calldata meta
    ) external returns (address vault, address token) {
        if (bytes(name).length == 0 || bytes(name).length > 48) revert InvalidName();
        if (bytes(symbol).length < 2 || bytes(symbol).length > 10) revert InvalidSymbol();
        if (maxSlippageBps == 0 || maxSlippageBps > MAX_SLIPPAGE_BPS) revert InvalidMaxSlippage();
        if (rebalanceInterval < MIN_REBALANCE_INTERVAL || rebalanceInterval > MAX_REBALANCE_INTERVAL) {
            revert InvalidInterval();
        }
        if (maxWeightBps == 0 || maxWeightBps > 10_000) revert InvalidMaxWeight();

        VaultParams memory p;
        p.name = name;
        p.symbol = symbol;
        p.usdg = usdg;
        p.oracle = priceOracle;
        p.venue = venue;
        p.guardian = guardian;
        p.constituents = constituents;
        p.maxWeightBps = maxWeightBps;
        p.maxSlippageBps = maxSlippageBps;
        p.rebalanceInterval = rebalanceInterval;
        p.maxPriceStaleness = maxPriceStaleness;
        p.depth = _validate(constituents, maxWeightBps);

        (vault, token) = IVaultDeployerV2(vaultDeployer).deploy(p);
        vaultOf[token] = vault;
        IMarketplaceRegistryV2(registry).registerStrategy(vault, token, msg.sender, meta);
        emit StrategyCreated(vault, token, msg.sender, p.depth);
    }

    function _validate(Constituent[] calldata constituents, uint16 maxWeightBps) private view returns (uint8 depth_) {
        uint256 n = constituents.length;
        if (n == 0) revert EmptyConstituents();
        if (n > MAX_CONSTITUENTS) revert TooManyConstituents();

        depth_ = 1;
        uint256 weightSum;
        for (uint256 i = 0; i < n; i++) {
            Constituent calldata c = constituents[i];
            if (c.token == address(0)) revert ZeroAddressConstituent();
            if (c.token == usdg) revert ConstituentIsUsdg();
            for (uint256 j = i + 1; j < n; j++) {
                if (constituents[j].token == c.token) revert DuplicateConstituent();
            }
            if (c.targetWeightBps < MIN_WEIGHT_BPS) revert WeightTooSmall(c.token);
            if (c.targetWeightBps > maxWeightBps) revert MaxWeightExceeded();
            weightSum += c.targetWeightBps;

            if (c.isStrategyToken) {
                address childVault = vaultOf[c.token];
                if (childVault == address(0)) revert UnknownStrategyToken();
                uint8 childDepth = _validateLeafChild(childVault);
                if (childDepth + 1 > depth_) depth_ = childDepth + 1;
            } else if (!IPriceOracleV2(priceOracle).isSupported(c.token) || !IVenue(venue).isSupported(c.token)) {
                revert UnsupportedConstituent(c.token);
            }
        }
        if (weightSum != 10_000) revert WeightsMustSumTo10000();
        if (depth_ > MAX_DEPTH) revert DepthExceeded();
    }

    function _validateLeafChild(address childVault) private view returns (uint8 childDepth) {
        childDepth = IStrategyVaultV2(childVault).depth();
        if (childDepth >= MAX_DEPTH) revert DepthExceeded();

        Constituent[] memory childConstituents = IStrategyVaultV2(childVault).getConstituents();
        for (uint256 i = 0; i < childConstituents.length; i++) {
            if (childConstituents[i].isStrategyToken) revert NestedTokenNotLeaf();
        }
    }
}
