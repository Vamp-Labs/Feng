// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMarketplaceRegistry {
    event StrategyRegistered(address indexed vault, address indexed token, address indexed creator);

    function registerStrategy(address vault, address token, address creator) external;

    function getAllStrategies() external view returns (address[] memory vaults);

    function getStrategyInfo(address vault)
        external
        view
        returns (address token, address creator, uint8 depth, uint256 createdAt);
}
