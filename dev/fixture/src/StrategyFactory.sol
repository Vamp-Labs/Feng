// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Constituent, StrategyVault} from "./StrategyVault.sol";
import {StrategyToken} from "./StrategyToken.sol";

interface IStockTokenMinter {
    function setMinter(address account, bool allowed) external;
}

interface INestedVault {
    function depth() external view returns (uint8);
}

interface INestedToken {
    function vault() external view returns (address);
}

interface IRegistry {
    function registerStrategy(address vault, address token, address creator) external;
}

contract StrategyFactory {
    uint8 public constant MAX_DEPTH = 2;

    address public immutable usdg;
    address public immutable oracle;
    address public immutable registry;

    event StrategyCreated(address indexed vault, address indexed token, address indexed creator, uint8 depth);

    constructor(address usdg_, address oracle_, address registry_) {
        usdg = usdg_;
        oracle = oracle_;
        registry = registry_;
    }

    function createStrategy(
        string calldata name,
        string calldata symbol,
        Constituent[] calldata constituents,
        uint16 maxWeightBps,
        uint256 rebalanceInterval
    ) external returns (address vault, address token) {
        require(constituents.length >= 2, "need >= 2 constituents");

        uint256 totalWeight;
        uint8 maxConstituentDepth;
        for (uint256 i = 0; i < constituents.length; i++) {
            totalWeight += constituents[i].targetWeightBps;
            for (uint256 j = i + 1; j < constituents.length; j++) {
                require(constituents[i].token != constituents[j].token, "duplicate constituent");
            }
            if (constituents[i].isStrategyToken) {
                address nestedVault = INestedToken(constituents[i].token).vault();
                uint8 nestedDepth = INestedVault(nestedVault).depth();
                if (nestedDepth > maxConstituentDepth) maxConstituentDepth = nestedDepth;
            }
        }
        require(totalWeight == 10_000, "weights must sum to 10000 bps");

        uint8 resultingDepth = maxConstituentDepth + 1;
        require(resultingDepth <= MAX_DEPTH, "exceeds max composition depth");

        StrategyVault newVault = new StrategyVault(
            address(this), usdg, oracle, constituents, maxWeightBps, rebalanceInterval, resultingDepth
        );
        vault = address(newVault);

        StrategyToken newToken = new StrategyToken(name, symbol, vault);
        token = address(newToken);
        newVault.setToken(token);

        for (uint256 i = 0; i < constituents.length; i++) {
            if (!constituents[i].isStrategyToken) {
                IStockTokenMinter(constituents[i].token).setMinter(vault, true);
            }
        }

        IRegistry(registry).registerStrategy(vault, token, msg.sender);

        emit StrategyCreated(vault, token, msg.sender, resultingDepth);
    }
}
