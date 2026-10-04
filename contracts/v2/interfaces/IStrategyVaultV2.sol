// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Constituent} from "../../interfaces/IStrategyVault.sol";

struct VaultParams {
    string name;
    string symbol;
    address usdg;
    address oracle;
    address venue;
    address guardian;
    Constituent[] constituents;
    uint16 maxWeightBps;
    uint16 maxSlippageBps;
    uint8 depth;
    uint256 rebalanceInterval;
    uint256 maxPriceStaleness;
}

interface IStrategyVaultV2 {
    event Deposit(address indexed sender, address indexed receiver, uint256 usdgAmount, uint256 shares);
    event DepositInKind(
        address indexed sender,
        address indexed receiver,
        address indexed token,
        uint256 amount,
        uint256 valueUsdg,
        uint256 shares
    );
    event Redeem(
        address indexed sender, address indexed receiver, address indexed owner, uint256 shares, uint256 usdgAmount
    );
    event RedeemInKind(address indexed sender, address indexed receiver, address indexed owner, uint256 shares);
    event LegTraded(address indexed token, bool buy, uint256 usdgAmount, uint256 tokenAmount);
    event Rebalanced(uint256 indexed timestamp, bool timeBased, bool thresholdBased, uint256 sharePrice);
    event NavCheckpoint(uint256 indexed timestamp, uint256 totalAssets, uint256 totalSupply);

    error ZeroAmount();
    error ZeroAddress();
    error ZeroShares();
    error ZeroAssets();
    error NoValueAdded();
    error EmptyConstituents();
    error TooManyConstituents();
    error WeightsMustSumTo10000();
    error UnsupportedDecimals(address token, uint8 decimals);
    error ConstituentIsUsdg();
    error InvalidMaxSlippage(uint16 maxSlippageBps);
    error StalePrice(address token, uint256 updatedAt);
    error SlippageExceeded(uint256 got, uint256 min);
    error InsufficientLiquidity(address token);
    error TokenNotConstituent(address token);
    error ExceedsMaxWeight(address token);
    error ChildRedeemFailed(address childToken, bytes reason);
    error RebalanceNotNeeded();
    error CheckpointTooSoon(uint256 nextAllowedAt);
    error NotGuardian();
    error InvalidSkipMask();

    function deposit(uint256 usdgAmount, address receiver, uint256 minShares) external returns (uint256 shares);

    function depositInKind(address token, uint256 amount, address receiver, uint256 minShares)
        external
        returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner, uint256 minUsdgOut)
        external
        returns (uint256 usdgOut);

    function redeemInKind(uint256 shares, address receiver, address owner)
        external
        returns (address[] memory tokens, uint256[] memory amounts);

    function redeemInKindExcluding(uint256 shares, address receiver, address owner, uint256 skipMask)
        external
        returns (address[] memory tokens, uint256[] memory amounts);

    function previewDeposit(uint256 usdgAmount) external view returns (uint256 shares);

    function previewDepositInKind(address token, uint256 amount) external view returns (uint256 shares);

    function previewRedeem(uint256 shares) external view returns (uint256 usdgOut);

    function totalAssetsUSDG() external view returns (uint256);

    function sharePrice() external view returns (uint256);

    function inceptionSharePrice() external view returns (uint256);

    function weights() external view returns (uint16[] memory currentBps);

    function effectiveMaxWeightBps(uint256 index) external view returns (uint16);

    function priceStatus() external view returns (bool fresh, uint256 oldestUpdatedAt);

    function getConstituents() external view returns (Constituent[] memory);

    function depth() external view returns (uint8);

    function rebalanceNeeded() external view returns (bool timeBased, bool thresholdBased);

    function executeRebalance() external;

    function checkpoint() external;

    function pause() external;

    function unpause() external;

    function paused() external view returns (bool);

    function token() external view returns (address);

    function usdgToken() external view returns (address);

    function usdgDecimals() external view returns (uint8);

    function priceOracle() external view returns (address);

    function venue() external view returns (address);

    function guardian() external view returns (address);

    function maxWeightBps() external view returns (uint16);

    function maxSlippageBps() external view returns (uint16);

    function rebalanceInterval() external view returns (uint256);

    function maxPriceStaleness() external view returns (uint256);

    function lastRebalanceTimestamp() external view returns (uint256);

    function lastCheckpointTimestamp() external view returns (uint256);
}
