// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRebalanceEngineV2 {
    event RebalancePerformed(address indexed vault, address indexed keeper);
    event CheckpointsRecorded(address indexed caller, uint256 requested, uint256 recorded);

    error ZeroAddress();
    error RebalanceNotNeeded(address vault);
    error NotRegisteredVault(address vault);

    function registry() external view returns (address);

    function MAX_SCAN() external view returns (uint256);

    function checkUpkeep() external view returns (address[] memory vaultsNeedingRebalance);

    function checkUpkeepRange(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory vaultsNeedingRebalance);

    function performRebalance(address vault) external;

    function checkpoint(address[] calldata vaults) external returns (uint256 recorded);
}
