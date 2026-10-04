// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {StrategyVault} from "./StrategyVault.sol";
import {StrategyToken} from "./StrategyToken.sol";
import {Constituent, IStrategyVault} from "./interfaces/IStrategyVault.sol";
import {IStrategyFactory} from "./interfaces/IStrategyFactory.sol";
import {IMarketplaceRegistry} from "./interfaces/IMarketplaceRegistry.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract StrategyFactory is IStrategyFactory {
    uint8 public constant MAX_DEPTH = 2;
    bytes32 public constant STOCK_MINTER_ROLE = keccak256("MINTER_ROLE");

    IMarketplaceRegistry public immutable registry;
    IPriceOracle public immutable priceOracle;
    address public immutable usdg;
    uint256 public immutable maxPriceStaleness;

    mapping(address => address) public vaultOf;

    error EmptyConstituents();
    error ZeroAddressConstituent();
    error DuplicateConstituent();
    error WeightsMustSumTo10000();
    error MaxWeightExceeded();
    error UnknownStrategyToken();
    error DepthExceeded();
    error NestedTokenNotLeaf();

    constructor(address registry_, address priceOracle_, address usdg_, uint256 maxPriceStaleness_) {
        require(registry_ != address(0) && priceOracle_ != address(0) && usdg_ != address(0), "zero address");
        registry = IMarketplaceRegistry(registry_);
        priceOracle = IPriceOracle(priceOracle_);
        usdg = usdg_;
        maxPriceStaleness = maxPriceStaleness_;
    }

    function createStrategy(
        string calldata name,
        string calldata symbol,
        Constituent[] calldata constituents,
        uint16 maxWeightBps,
        uint256 rebalanceInterval
    ) external returns (address vault, address token) {
        uint256 n = constituents.length;
        if (n == 0) revert EmptyConstituents();

        uint256 weightSum;
        uint8 depth_ = 1;
        for (uint256 i = 0; i < n; i++) {
            Constituent calldata c = constituents[i];
            if (c.token == address(0)) revert ZeroAddressConstituent();
            for (uint256 j = i + 1; j < n; j++) {
                if (constituents[j].token == c.token) revert DuplicateConstituent();
            }
            weightSum += c.targetWeightBps;
            if (c.targetWeightBps > maxWeightBps) revert MaxWeightExceeded();

            if (c.isStrategyToken) {
                address childVault = vaultOf[c.token];
                if (childVault == address(0)) revert UnknownStrategyToken();
                uint8 childDepth = _validateLeafChild(childVault);
                if (childDepth + 1 > depth_) depth_ = childDepth + 1;
            }
        }
        if (weightSum != 10_000) revert WeightsMustSumTo10000();
        if (depth_ > MAX_DEPTH) revert DepthExceeded();

        Constituent[] memory constituentsMem = new Constituent[](n);
        for (uint256 i = 0; i < n; i++) {
            constituentsMem[i] = constituents[i];
        }

        vault = address(
            new StrategyVault(
                name,
                symbol,
                usdg,
                address(priceOracle),
                constituentsMem,
                maxWeightBps,
                rebalanceInterval,
                depth_,
                maxPriceStaleness
            )
        );
        token = address(StrategyVault(vault).token());

        for (uint256 i = 0; i < n; i++) {
            if (!constituents[i].isStrategyToken) {
                IAccessControl(constituents[i].token).grantRole(STOCK_MINTER_ROLE, vault);
            }
        }

        vaultOf[token] = vault;
        registry.registerStrategy(vault, token, msg.sender);

        emit StrategyCreated(vault, token, msg.sender, depth_);
    }

    function _validateLeafChild(address childVault) private view returns (uint8 childDepth) {
        childDepth = IStrategyVault(childVault).depth();
        if (childDepth >= MAX_DEPTH) revert DepthExceeded();

        Constituent[] memory childConstituents = IStrategyVault(childVault).getConstituents();
        for (uint256 i = 0; i < childConstituents.length; i++) {
            if (childConstituents[i].isStrategyToken) revert NestedTokenNotLeaf();
        }
    }
}
