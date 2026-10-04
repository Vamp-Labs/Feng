// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMarketplaceRegistryV2} from "./interfaces/IMarketplaceRegistryV2.sol";
import {IRebalanceEngineV2} from "./interfaces/IRebalanceEngineV2.sol";
import {IStrategyVaultV2} from "./interfaces/IStrategyVaultV2.sol";

contract RebalanceEngineV2 is IRebalanceEngineV2 {
    uint256 public constant MAX_SCAN = 200;

    address public immutable registry;

    constructor(address registry_) {
        if (registry_ == address(0)) revert ZeroAddress();
        registry = registry_;
    }

    function checkUpkeep() external view returns (address[] memory) {
        return _scan(0, MAX_SCAN);
    }

    function checkUpkeepRange(uint256 offset, uint256 limit) external view returns (address[] memory) {
        return _scan(offset, limit);
    }

    function performRebalance(address vault) external {
        if (!IMarketplaceRegistryV2(registry).isRegistered(vault)) revert NotRegisteredVault(vault);
        (bool timeBased, bool thresholdBased) = IStrategyVaultV2(vault).rebalanceNeeded();
        if (!timeBased && !thresholdBased) revert RebalanceNotNeeded(vault);
        IStrategyVaultV2(vault).executeRebalance();
        emit RebalancePerformed(vault, msg.sender);
    }

    function checkpoint(address[] calldata vaults) external returns (uint256 recorded) {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (!IMarketplaceRegistryV2(registry).isRegistered(vaults[i])) continue;
            try IStrategyVaultV2(vaults[i]).checkpoint() {
                recorded++;
            } catch {}
        }
        emit CheckpointsRecorded(msg.sender, vaults.length, recorded);
    }

    function _scan(uint256 offset, uint256 limit) private view returns (address[] memory result) {
        address[] memory page = IMarketplaceRegistryV2(registry).getStrategies(offset, limit);
        address[] memory buffer = new address[](page.length);
        uint256 count;
        for (uint256 i = 0; i < page.length; i++) {
            try IStrategyVaultV2(page[i]).rebalanceNeeded() returns (bool timeBased, bool thresholdBased) {
                if (timeBased || thresholdBased) buffer[count++] = page[i];
            } catch {}
        }
        result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = buffer[i];
        }
    }
}
