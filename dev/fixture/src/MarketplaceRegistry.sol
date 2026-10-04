// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IVaultDepth {
    function depth() external view returns (uint8);
}

contract MarketplaceRegistry is Ownable {
    struct StrategyInfo {
        address token;
        address creator;
        uint8 depth;
        uint256 createdAt;
    }

    address public factory;
    address[] private _vaults;
    mapping(address => StrategyInfo) private _info;

    event StrategyRegistered(address indexed vault, address indexed token, address indexed creator);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setFactory(address factory_) external onlyOwner {
        require(factory == address(0), "factory already set");
        factory = factory_;
    }

    function registerStrategy(address vault, address token, address creator) external {
        require(msg.sender == factory, "not factory");
        _vaults.push(vault);
        _info[vault] =
            StrategyInfo({token: token, creator: creator, depth: IVaultDepth(vault).depth(), createdAt: block.timestamp});
        emit StrategyRegistered(vault, token, creator);
    }

    function getAllStrategies() external view returns (address[] memory vaults) {
        return _vaults;
    }

    function getStrategyInfo(address vault)
        external
        view
        returns (address token, address creator, uint8 depth, uint256 createdAt)
    {
        StrategyInfo memory info = _info[vault];
        return (info.token, info.creator, info.depth, info.createdAt);
    }
}
