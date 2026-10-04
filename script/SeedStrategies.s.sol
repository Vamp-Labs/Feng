// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {MockUSDG} from "../contracts/mocks/MockUSDG.sol";
import {MockV3Aggregator} from "../contracts/mocks/MockV3Aggregator.sol";
import {StrategyFactory} from "../contracts/StrategyFactory.sol";
import {Constituent, IStrategyVault} from "../contracts/interfaces/IStrategyVault.sol";

contract SeedStrategies is Script {
    uint256 internal constant TSLA = 0;
    uint256 internal constant AMZN = 1;
    uint256 internal constant NFLX = 2;
    uint256 internal constant PLTR = 3;
    uint256 internal constant AMD = 4;
    uint256 internal constant COUNT = 10;

    StrategyFactory internal factory;
    MockUSDG internal usdg;
    address[5] internal stocks;
    address[5] internal stockFeeds;
    address internal usdgFeed;
    address[COUNT] internal vaults;
    address[COUNT] internal tokens;

    function run() external {
        string memory network = vm.envOr("DEPLOY_NETWORK", string("robinhood-testnet"));
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        _loadAddresses(string.concat("deployments/", network, "/addresses.json"));

        vm.startBroadcast(deployerKey);

        _pushPrices([int256(250e8), 180e8, 600e8, 25e8, 140e8]);
        usdg.mint(deployer, 50_000 * 10 ** IERC20Metadata(address(usdg)).decimals());

        _createAll();
        _seedDeposits(deployer);
        _pushPrices([int256(260e8), 183e8, 581e8, 26e8, 138e8]);

        vm.stopBroadcast();

        for (uint256 i = 0; i < COUNT; i++) {
            console2.log("Strategy", i + 1, vaults[i]);
        }
    }

    function _loadAddresses(string memory path) internal {
        string memory json = vm.readFile(path);
        factory = StrategyFactory(vm.parseJsonAddress(json, ".strategyFactory"));
        usdg = MockUSDG(vm.parseJsonAddress(json, ".usdg"));
        usdgFeed = vm.parseJsonAddress(json, ".priceOracles.USDG");

        string[5] memory tickers = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];
        for (uint256 i = 0; i < 5; i++) {
            stocks[i] = vm.parseJsonAddress(json, string.concat(".stockTokens.", tickers[i]));
            stockFeeds[i] = vm.parseJsonAddress(json, string.concat(".priceOracles.", tickers[i]));
        }
    }

    function _pushPrices(int256[5] memory prices) internal {
        MockV3Aggregator(usdgFeed).updateAnswer(1e8);
        for (uint256 i = 0; i < 5; i++) {
            MockV3Aggregator(stockFeeds[i]).updateAnswer(prices[i]);
        }
    }

    function _createAll() internal {
        _create(0, "AI Growth", "AIGR", _three(_s(PLTR, 3500), _s(AMD, 3500), _s(AMZN, 3000)), 4000, 7 days);
        _create(1, "Streaming Giants", "STRM", _two(_s(NFLX, 6000), _s(AMZN, 4000)), 6000, 3 days);
        _create(2, "EV Momentum", "EVMO", _three(_s(TSLA, 4000), _s(AMD, 3000), _s(PLTR, 3000)), 4000, 1 days);
        _create(
            3,
            "Big Five Equal",
            "EQ5",
            _five(_s(TSLA, 2000), _s(AMZN, 2000), _s(NFLX, 2000), _s(PLTR, 2000), _s(AMD, 2000)),
            2000,
            7 days
        );
        _create(4, "Defensive Core", "DEFC", _three(_s(AMZN, 4000), _s(NFLX, 3000), _s(AMD, 3000)), 4000, 7 days);
        _create(5, "Chip Tilt", "CHIP", _two(_s(AMD, 6000), _s(TSLA, 4000)), 6000, 14 days);
        _create(6, "High Beta Blitz", "BLTZ", _two(_s(PLTR, 5000), _s(TSLA, 5000)), 5000, 1 hours);
        _create(7, "Cloud & Commerce", "CLCM", _three(_s(AMZN, 5000), _s(PLTR, 2500), _s(NFLX, 2500)), 5000, 7 days);
        _create(8, "Core Satellite", "CORE", _three(_t(0, 4000), _t(3, 4000), _s(TSLA, 2000)), 4000, 7 days);
        _create(9, "Conviction Mix", "CONV", _three(_t(1, 4000), _t(5, 3000), _s(PLTR, 3000)), 4000, 1 days);
    }

    function _seedDeposits(address deployer) internal {
        uint256[COUNT] memory amounts = [uint256(5000), 2500, 3000, 4000, 1500, 1000, 2000, 2500, 3500, 1200];
        uint256 unit = 10 ** IERC20Metadata(address(usdg)).decimals();
        for (uint256 i = 0; i < COUNT; i++) {
            usdg.approve(vaults[i], amounts[i] * unit);
            IStrategyVault(vaults[i]).deposit(amounts[i] * unit, deployer);
        }
    }

    function _create(
        uint256 index,
        string memory name,
        string memory symbol,
        Constituent[] memory constituents,
        uint16 maxWeightBps,
        uint256 interval
    ) internal {
        (address vault, address token) = factory.createStrategy(name, symbol, constituents, maxWeightBps, interval);
        vaults[index] = vault;
        tokens[index] = token;
    }

    function _s(uint256 stock, uint16 weightBps) internal view returns (Constituent memory) {
        return Constituent({token: stocks[stock], targetWeightBps: weightBps, isStrategyToken: false});
    }

    function _t(uint256 index, uint16 weightBps) internal view returns (Constituent memory) {
        return Constituent({token: tokens[index], targetWeightBps: weightBps, isStrategyToken: true});
    }

    function _two(Constituent memory a, Constituent memory b) internal pure returns (Constituent[] memory list) {
        list = new Constituent[](2);
        list[0] = a;
        list[1] = b;
    }

    function _three(Constituent memory a, Constituent memory b, Constituent memory c)
        internal
        pure
        returns (Constituent[] memory list)
    {
        list = new Constituent[](3);
        list[0] = a;
        list[1] = b;
        list[2] = c;
    }

    function _five(
        Constituent memory a,
        Constituent memory b,
        Constituent memory c,
        Constituent memory d,
        Constituent memory e
    ) internal pure returns (Constituent[] memory list) {
        list = new Constituent[](5);
        list[0] = a;
        list[1] = b;
        list[2] = c;
        list[3] = d;
        list[4] = e;
    }
}
