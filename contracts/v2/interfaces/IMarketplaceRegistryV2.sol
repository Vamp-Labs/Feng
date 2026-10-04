// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct StrategyMeta {
    string description;
    string[] tags;
}

struct StrategyInfoV2 {
    address vault;
    address token;
    address creator;
    uint8 depth;
    uint256 createdAt;
    string description;
    string[] tags;
}

interface IMarketplaceRegistryV2 {
    event StrategyRegistered(address indexed vault, address indexed token, address indexed creator);
    event MetaUpdated(address indexed vault, string description, string[] tags);

    error ZeroAddress();
    error AlreadyRegistered();
    error NotRegistered();
    error NotCreator();
    error DescriptionTooLong();
    error TooManyTags();
    error InvalidTag();
    error DuplicateTag();

    function registerStrategy(address vault, address token, address creator, StrategyMeta calldata meta) external;

    function updateMeta(address vault, StrategyMeta calldata meta) external;

    function getAllStrategies() external view returns (address[] memory vaults);

    function getStrategies(uint256 offset, uint256 limit) external view returns (address[] memory vaults);

    function strategyCount() external view returns (uint256);

    function isRegistered(address vault) external view returns (bool);

    function getStrategyInfo(address vault)
        external
        view
        returns (address token, address creator, uint8 depth, uint256 createdAt);

    function getStrategyInfoV2(address vault) external view returns (StrategyInfoV2 memory);

    function getStrategyMeta(address vault) external view returns (StrategyMeta memory);
}
