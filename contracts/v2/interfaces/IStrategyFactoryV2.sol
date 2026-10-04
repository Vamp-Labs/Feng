// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Constituent} from "../../interfaces/IStrategyVault.sol";
import {StrategyMeta} from "./IMarketplaceRegistryV2.sol";
import {VaultParams} from "./IStrategyVaultV2.sol";

interface IVaultDeployerV2 {
    function deploy(VaultParams calldata params) external returns (address vault, address token);
}

interface IStrategyFactoryV2 {
    event StrategyCreated(address indexed vault, address indexed token, address indexed creator, uint8 depth);

    error ZeroAddress();
    error EmptyConstituents();
    error TooManyConstituents();
    error ZeroAddressConstituent();
    error DuplicateConstituent();
    error ConstituentIsUsdg();
    error UnsupportedConstituent(address token);
    error WeightsMustSumTo10000();
    error WeightTooSmall(address token);
    error MaxWeightExceeded();
    error InvalidMaxWeight();
    error InvalidInterval();
    error InvalidMaxSlippage();
    error InvalidName();
    error InvalidSymbol();
    error UnknownStrategyToken();
    error DepthExceeded();
    error NestedTokenNotLeaf();
    error UnsupportedUsdgDecimals(uint8 decimals);
    error VenueUsdgMismatch();

    function createStrategy(
        string calldata name,
        string calldata symbol,
        Constituent[] calldata constituents,
        uint16 maxWeightBps,
        uint256 rebalanceInterval,
        uint16 maxSlippageBps,
        StrategyMeta calldata meta
    ) external returns (address vault, address token);

    function vaultOf(address token) external view returns (address);

    function registry() external view returns (address);

    function priceOracle() external view returns (address);

    function venue() external view returns (address);

    function usdg() external view returns (address);

    function usdgDecimals() external view returns (uint8);

    function guardian() external view returns (address);

    function vaultDeployer() external view returns (address);

    function maxPriceStaleness() external view returns (uint256);

    function MAX_DEPTH() external view returns (uint8);

    function MAX_CONSTITUENTS() external view returns (uint8);

    function MIN_WEIGHT_BPS() external view returns (uint16);

    function MAX_SLIPPAGE_BPS() external view returns (uint16);

    function MIN_REBALANCE_INTERVAL() external view returns (uint256);

    function MAX_REBALANCE_INTERVAL() external view returns (uint256);
}
