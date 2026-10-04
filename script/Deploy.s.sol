// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {MockUSDG} from "../contracts/mocks/MockUSDG.sol";
import {MockStockToken} from "../contracts/mocks/MockStockToken.sol";
import {MockV3Aggregator} from "../contracts/mocks/MockV3Aggregator.sol";
import {ChainlinkPriceOracle} from "../contracts/oracle/ChainlinkPriceOracle.sol";
import {MarketplaceRegistry} from "../contracts/MarketplaceRegistry.sol";
import {StrategyFactory} from "../contracts/StrategyFactory.sol";
import {RebalanceEngine} from "../contracts/RebalanceEngine.sol";

contract Deploy is Script {
    uint256 internal constant MAX_PRICE_STALENESS = 24 hours;
    uint256 internal constant TICKER_COUNT = 5;

    struct Deployed {
        address usdg;
        address usdgFeed;
        address factory;
        address engine;
        address registry;
        address[TICKER_COUNT] stockTokens;
        address[TICKER_COUNT] feeds;
    }

    function run() external {
        string memory network = vm.envOr("DEPLOY_NETWORK", string("anvil"));
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string[TICKER_COUNT] memory tickers = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];
        int256[TICKER_COUNT] memory initialPrices =
            [int256(250e8), int256(180e8), int256(600e8), int256(25e8), int256(140e8)];

        Deployed memory d;

        vm.startBroadcast(deployerKey);
        d = _deploy(deployer, tickers, initialPrices);
        vm.stopBroadcast();

        _writeAddresses(network, tickers, d);

        console2.log("Deployed to network:", network);
        console2.log("MockUSDG:", d.usdg);
        console2.log("StrategyFactory:", d.factory);
        console2.log("RebalanceEngine:", d.engine);
        console2.log("MarketplaceRegistry:", d.registry);
    }

    function _deploy(address deployer, string[TICKER_COUNT] memory tickers, int256[TICKER_COUNT] memory initialPrices)
        internal
        returns (Deployed memory d)
    {
        MockUSDG usdg = new MockUSDG(deployer);
        d.usdg = address(usdg);

        MockStockToken[TICKER_COUNT] memory stockTokens;
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            stockTokens[i] = new MockStockToken(string.concat("Mock ", tickers[i]), tickers[i], deployer, 1e18);
            d.stockTokens[i] = address(stockTokens[i]);
            d.feeds[i] = address(new MockV3Aggregator(8, initialPrices[i]));
        }

        d.usdgFeed = address(new MockV3Aggregator(8, int256(1e8)));

        ChainlinkPriceOracle oracle = new ChainlinkPriceOracle(deployer);
        oracle.setFeed(d.usdg, d.usdgFeed);
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            oracle.setFeed(d.stockTokens[i], d.feeds[i]);
        }

        MarketplaceRegistry registry = new MarketplaceRegistry(deployer);
        d.registry = address(registry);

        StrategyFactory factory = new StrategyFactory(d.registry, address(oracle), d.usdg, MAX_PRICE_STALENESS);
        d.factory = address(factory);

        RebalanceEngine engine = new RebalanceEngine(d.registry);
        d.engine = address(engine);

        registry.grantRole(registry.FACTORY_ROLE(), d.factory);

        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            stockTokens[i].grantRole(stockTokens[i].DEFAULT_ADMIN_ROLE(), d.factory);
        }
    }

    function _networkInfo(string memory network)
        internal
        pure
        returns (uint256 chainId, string memory rpcUrl, string memory explorerUrl)
    {
        bytes32 h = keccak256(bytes(network));
        if (h == keccak256(bytes("robinhood-testnet"))) {
            return (46630, "https://rpc.testnet.chain.robinhood.com", "https://explorer.testnet.chain.robinhood.com");
        } else if (h == keccak256(bytes("arbitrum-sepolia"))) {
            return (421614, "https://sepolia-rollup.arbitrum.io/rpc", "https://sepolia.arbiscan.io");
        } else {
            return (31337, "http://127.0.0.1:8545", "");
        }
    }

    function _tickerMapJson(string[TICKER_COUNT] memory tickers, address[TICKER_COUNT] memory values)
        internal
        pure
        returns (string memory result)
    {
        result = "{";
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            result =
                string.concat(result, i == 0 ? "" : ",", "\"", tickers[i], "\":\"", vm.toString(values[i]), "\"");
        }
        result = string.concat(result, "}");
    }

    function _priceOraclesJson(string[TICKER_COUNT] memory tickers, Deployed memory d)
        internal
        pure
        returns (string memory result)
    {
        result = string.concat("{\"USDG\":\"", vm.toString(d.usdgFeed), "\"");
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            result = string.concat(result, ",\"", tickers[i], "\":\"", vm.toString(d.feeds[i]), "\"");
        }
        result = string.concat(result, "}");
    }

    function _headJson(string memory network, address usdg) internal pure returns (string memory) {
        (uint256 chainId, string memory rpcUrl, string memory explorerUrl) = _networkInfo(network);
        return string.concat(
            "{\n",
            "  \"chainId\": ",
            vm.toString(chainId),
            ",\n",
            "  \"rpcUrl\": \"",
            rpcUrl,
            "\",\n",
            "  \"explorerUrl\": \"",
            explorerUrl,
            "\",\n",
            "  \"usdg\": \"",
            vm.toString(usdg),
            "\",\n"
        );
    }

    function _tailJson(Deployed memory d) internal pure returns (string memory) {
        return string.concat(
            "  \"strategyFactory\": \"",
            vm.toString(d.factory),
            "\",\n",
            "  \"rebalanceEngine\": \"",
            vm.toString(d.engine),
            "\",\n",
            "  \"marketplaceRegistry\": \"",
            vm.toString(d.registry),
            "\"\n",
            "}\n"
        );
    }

    function _writeAddresses(string memory network, string[TICKER_COUNT] memory tickers, Deployed memory d)
        internal
    {
        string memory stockTokensJson = _tickerMapJson(tickers, d.stockTokens);
        string memory priceOraclesJson = _priceOraclesJson(tickers, d);
        string memory head = _headJson(network, d.usdg);
        string memory tail = _tailJson(d);

        string memory json = string.concat(
            head, "  \"stockTokens\": ", stockTokensJson, ",\n  \"priceOracles\": ", priceOraclesJson, ",\n", tail
        );

        string memory path = string.concat("deployments/", network, "/addresses.json");
        vm.writeFile(path, json);
    }
}
