// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMarketplaceRegistry} from "./interfaces/IMarketplaceRegistry.sol";
import {IStrategyVault} from "./interfaces/IStrategyVault.sol";

contract MarketplaceRegistry is AccessControl, IMarketplaceRegistry {
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    struct StrategyInfo {
        address token;
        address creator;
        uint8 depth;
        uint256 createdAt;
    }

    address[] private _strategies;
    mapping(address => StrategyInfo) private _strategyInfo;
    mapping(address => bool) private _registered;

    error AlreadyRegistered();
    error NotRegistered();

    constructor(address admin) {
        require(admin != address(0), "zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function registerStrategy(address vault, address token, address creator) external onlyRole(FACTORY_ROLE) {
        if (_registered[vault]) revert AlreadyRegistered();
        _registered[vault] = true;
        _strategies.push(vault);
        _strategyInfo[vault] = StrategyInfo({
            token: token,
            creator: creator,
            depth: IStrategyVault(vault).depth(),
            createdAt: block.timestamp
        });
        emit StrategyRegistered(vault, token, creator);
    }

    function getAllStrategies() external view returns (address[] memory vaults) {
        return _strategies;
    }

    function getStrategyInfo(address vault)
        external
        view
        returns (address token, address creator, uint8 depth, uint256 createdAt)
    {
        if (!_registered[vault]) revert NotRegistered();
        StrategyInfo memory info = _strategyInfo[vault];
        return (info.token, info.creator, info.depth, info.createdAt);
    }
}
