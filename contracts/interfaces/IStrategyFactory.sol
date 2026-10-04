// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Constituent} from "./IStrategyVault.sol";

interface IStrategyFactory {
    event StrategyCreated(address indexed vault, address indexed token, address indexed creator, uint8 depth);

    function createStrategy(
        string calldata name,
        string calldata symbol,
        Constituent[] calldata constituents,
        uint16 maxWeightBps,
        uint256 rebalanceInterval
    ) external returns (address vault, address token);
}
