// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {MockStockToken} from "../contracts/mocks/MockStockToken.sol";
import {FengAggregator} from "../contracts/v2/oracle/FengAggregator.sol";
import {ChainlinkPriceOracleV2} from "../contracts/v2/oracle/ChainlinkPriceOracleV2.sol";
import {OracleDesk} from "../contracts/v2/venue/OracleDesk.sol";
import {IOracleDesk} from "../contracts/v2/interfaces/IOracleDesk.sol";
import {SocialRegistry} from "../contracts/v2/SocialRegistry.sol";

contract AddAssetsV2 is Script {
    uint256 internal constant TICKER_COUNT = 8;
    uint8 internal constant FEED_DECIMALS = 8;
    uint16 internal constant AGGREGATOR_MAX_DEVIATION_BPS = 1000;
    uint16 internal constant AGGREGATOR_MAX_SHOCK_BPS = 3000;

    address internal oracle;
    address internal desk;
    address internal deployer;
    address internal relayer;

    address[TICKER_COUNT] internal tokens;
    address[TICKER_COUNT] internal feeds;

    function _tickers() internal pure returns (string[TICKER_COUNT] memory) {
        return ["NVDA", "TSMC", "MSFT", "GOOGL", "RKLB", "ISRG", "XOM", "ENPH"];
    }

    function _initPrices() internal pure returns (int256[TICKER_COUNT] memory p) {
        p[0] = 18650000000;
        p[1] = 22600000000;
        p[2] = 51400000000;
        p[3] = 19800000000;
        p[4] = 2900000000;
        p[5] = 59800000000;
        p[6] = 11300000000;
        p[7] = 4950000000;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerKey);
        string memory network = vm.envOr("DEPLOY_NETWORK", string("robinhood-testnet"));
        string memory path = string.concat("deployments/", network, "-v2/addresses.json");

        string memory json = vm.readFile(path);
        oracle = vm.parseJsonAddress(json, ".oracle");
        desk = vm.parseJsonAddress(json, ".venue");
        relayer = vm.envOr("RELAYER_ADDRESS", deployer);

        bool deploySocial = vm.envOr("DEPLOY_SOCIAL_REGISTRY", true);
        address socialRegistry;

        vm.startBroadcast(deployerKey);
        _addAssets();
        if (deploySocial) {
            socialRegistry = address(new SocialRegistry());
            console2.log("SocialRegistry:", socialRegistry);
        }
        vm.stopBroadcast();

        if (vm.envOr("WRITE_ADDRESSES", false)) {
            _writeAddresses(path, socialRegistry, deploySocial);
        } else {
            console2.log("WRITE_ADDRESSES is not set, deployment file not updated");
        }

        string[TICKER_COUNT] memory tickers = _tickers();
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            console2.log(tickers[i], tokens[i], feeds[i]);
        }
    }

    function _addAssets() internal {
        string[TICKER_COUNT] memory tickers = _tickers();
        int256[TICKER_COUNT] memory prices = _initPrices();

        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            MockStockToken token = new MockStockToken(string.concat("Mock ", tickers[i]), tickers[i], deployer, 1e18);
            tokens[i] = address(token);

            FengAggregator feed = new FengAggregator(
                deployer,
                FEED_DECIMALS,
                string.concat(tickers[i], " / USD"),
                prices[i],
                AGGREGATOR_MAX_DEVIATION_BPS,
                AGGREGATOR_MAX_SHOCK_BPS
            );
            feeds[i] = address(feed);
            feed.grantRole(feed.UPDATER_ROLE(), relayer);

            ChainlinkPriceOracleV2(oracle).setFeed(address(token), address(feed));
            OracleDesk(desk).setToken(address(token), IOracleDesk.Mode.Mint);
            token.grantRole(token.MINTER_ROLE(), desk);
        }
    }

    function _writeAddresses(string memory path, address socialRegistry, bool deploySocial) internal {
        string[TICKER_COUNT] memory tickers = _tickers();
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            vm.writeJson(vm.toString(tokens[i]), path, string.concat(".stockTokens.", tickers[i]));
            vm.writeJson(vm.toString(feeds[i]), path, string.concat(".priceOracles.", tickers[i]));
        }
        if (deploySocial) {
            vm.writeJson(vm.toString(socialRegistry), path, ".socialRegistry");
        }
    }
}
