// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebalanceEngine} from "./interfaces/IRebalanceEngine.sol";
import {IMarketplaceRegistry} from "./interfaces/IMarketplaceRegistry.sol";
import {IStrategyVault} from "./interfaces/IStrategyVault.sol";

contract RebalanceEngine is IRebalanceEngine {
    IMarketplaceRegistry public immutable registry;

    error RebalanceNotNeeded(address vault);

    constructor(address registry_) {
        require(registry_ != address(0), "zero registry");
        registry = IMarketplaceRegistry(registry_);
    }

    function checkUpkeep() external view returns (address[] memory vaultsNeedingRebalance) {
        address[] memory all = registry.getAllStrategies();
        address[] memory buffer = new address[](all.length);
        uint256 count;

        for (uint256 i = 0; i < all.length; i++) {
            (bool timeBased, bool thresholdBased) = IStrategyVault(all[i]).rebalanceNeeded();
            if (timeBased || thresholdBased) {
                buffer[count] = all[i];
                count++;
            }
        }

        vaultsNeedingRebalance = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            vaultsNeedingRebalance[i] = buffer[i];
        }
    }

    function performRebalance(address vault) external {
        (bool timeBased, bool thresholdBased) = IStrategyVault(vault).rebalanceNeeded();
        if (!timeBased && !thresholdBased) revert RebalanceNotNeeded(vault);
        IStrategyVault(vault).executeRebalance();
    }
}
