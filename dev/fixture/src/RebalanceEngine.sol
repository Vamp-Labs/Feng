// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRegistry {
    function getAllStrategies() external view returns (address[] memory vaults);
}

interface IRebalanceableVault {
    function rebalanceNeeded() external view returns (bool timeBased, bool thresholdBased);
    function executeRebalance() external;
}

contract RebalanceEngine {
    address public immutable registry;

    constructor(address registry_) {
        registry = registry_;
    }

    function checkUpkeep() external view returns (address[] memory vaultsNeedingRebalance) {
        address[] memory all = IRegistry(registry).getAllStrategies();
        uint256 count;
        for (uint256 i = 0; i < all.length; i++) {
            (bool timeBased, bool thresholdBased) = IRebalanceableVault(all[i]).rebalanceNeeded();
            if (timeBased || thresholdBased) count++;
        }

        vaultsNeedingRebalance = new address[](count);
        uint256 cursor;
        for (uint256 i = 0; i < all.length; i++) {
            (bool timeBased, bool thresholdBased) = IRebalanceableVault(all[i]).rebalanceNeeded();
            if (timeBased || thresholdBased) {
                vaultsNeedingRebalance[cursor] = all[i];
                cursor++;
            }
        }
    }

    function performRebalance(address vault) external {
        (bool timeBased, bool thresholdBased) = IRebalanceableVault(vault).rebalanceNeeded();
        require(timeBased || thresholdBased, "rebalance not needed");
        IRebalanceableVault(vault).executeRebalance();
    }
}
