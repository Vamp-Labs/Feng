// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRebalanceEngine {
    function checkUpkeep() external view returns (address[] memory vaultsNeedingRebalance);

    function performRebalance(address vault) external;
}
