// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockUSDG} from "../src/MockUSDG.sol";
import {MockStockToken} from "../src/MockStockToken.sol";
import {MockPriceOracle} from "../src/MockPriceOracle.sol";
import {MarketplaceRegistry} from "../src/MarketplaceRegistry.sol";
import {StrategyFactory} from "../src/StrategyFactory.sol";
import {RebalanceEngine} from "../src/RebalanceEngine.sol";

contract Deploy is Script {
    string[5] symbols = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];
    uint256[5] prices = [250 ether, 180 ether, 650 ether, 70 ether, 140 ether];

    function run() external {
        uint256 deployerKey = vm.envOr(
            "DEPLOYER_PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        MockUSDG usdg = new MockUSDG();
        MockPriceOracle oracle = new MockPriceOracle(deployer);
        oracle.setPrice(address(usdg), 1 ether);

        MockStockToken[5] memory stockTokens;
        for (uint256 i = 0; i < symbols.length; i++) {
            stockTokens[i] = new MockStockToken(string.concat("Mock ", symbols[i]), symbols[i], deployer);
            oracle.setPrice(address(stockTokens[i]), prices[i]);
        }

        MarketplaceRegistry registry = new MarketplaceRegistry(deployer);
        StrategyFactory factory = new StrategyFactory(address(usdg), address(oracle), address(registry));
        registry.setFactory(address(factory));

        for (uint256 i = 0; i < symbols.length; i++) {
            stockTokens[i].transferOwnership(address(factory));
        }

        RebalanceEngine rebalanceEngine = new RebalanceEngine(address(registry));

        vm.stopBroadcast();

        string memory stockTokensJson;
        string memory priceOraclesJson;
        for (uint256 i = 0; i < symbols.length; i++) {
            stockTokensJson = vm.serializeAddress("stockTokens", symbols[i], address(stockTokens[i]));
            priceOraclesJson = vm.serializeAddress("priceOracles", symbols[i], address(oracle));
        }
        priceOraclesJson = vm.serializeAddress("priceOracles", "USDG", address(oracle));

        string memory root = "root";
        vm.serializeUint(root, "chainId", block.chainid);
        vm.serializeString(root, "rpcUrl", "http://127.0.0.1:8545");
        vm.serializeString(root, "explorerUrl", "");
        vm.serializeAddress(root, "usdg", address(usdg));
        vm.serializeString(root, "stockTokens", stockTokensJson);
        vm.serializeString(root, "priceOracles", priceOraclesJson);
        vm.serializeAddress(root, "strategyFactory", address(factory));
        vm.serializeAddress(root, "rebalanceEngine", address(rebalanceEngine));
        string memory finalJson = vm.serializeAddress(root, "marketplaceRegistry", address(registry));

        vm.writeJson(finalJson, "../../src/lib/dev/anvil-addresses.json");
    }
}
