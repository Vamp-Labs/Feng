// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockStockToken} from "../contracts/mocks/MockStockToken.sol";
import {MockUSDGV2} from "../contracts/v2/mocks/MockUSDGV2.sol";
import {FengAggregator} from "../contracts/v2/oracle/FengAggregator.sol";
import {ChainlinkPriceOracleV2} from "../contracts/v2/oracle/ChainlinkPriceOracleV2.sol";
import {OracleDesk} from "../contracts/v2/venue/OracleDesk.sol";
import {IOracleDesk} from "../contracts/v2/interfaces/IOracleDesk.sol";
import {FengFaucet} from "../contracts/v2/faucet/FengFaucet.sol";
import {MarketplaceRegistryV2} from "../contracts/v2/MarketplaceRegistryV2.sol";
import {VaultDeployerV2} from "../contracts/v2/VaultDeployerV2.sol";
import {StrategyFactoryV2} from "../contracts/v2/StrategyFactoryV2.sol";
import {RebalanceEngineV2} from "../contracts/v2/RebalanceEngineV2.sol";
import {StrategyLens} from "../contracts/v2/StrategyLens.sol";

contract DeployV2 is Script {
    error RelayerAddressRequired();
    error RelayerAddressIsDeployer();
    error FaucetAddressRequired();
    error FaucetAddressIsDeployer();
    error FaucetFundingFailed();

    uint256 internal constant TICKER_COUNT = 5;
    uint256 internal constant DEFAULT_MAX_PRICE_STALENESS = 12 hours;
    uint16 internal constant DESK_SPREAD_BPS = 10;
    uint16 internal constant DEFAULT_MAX_SLIPPAGE_BPS = 100;
    uint16 internal constant AGGREGATOR_MAX_DEVIATION_BPS = 1000;
    uint16 internal constant AGGREGATOR_MAX_SHOCK_BPS = 3000;
    uint8 internal constant FEED_DECIMALS = 8;
    uint256 internal constant RESERVE_WHOLE_USDG = 10_000_000;
    uint256 internal constant FAUCET_USDG_WHOLE = 10_000;
    uint256 internal constant FAUCET_ETH_PER_CLAIM = 0.0001 ether;
    uint256 internal constant DEFAULT_FAUCET_DAILY_CAP = 40;
    uint256 internal constant DEFAULT_SANDBOX_MAX_SWAP_WHOLE_USDG = 5000;
    bytes32 internal constant TESTNET_HASH = keccak256("robinhood-testnet");
    uint256 internal constant CHECKPOINT_MIN_INTERVAL = 30 minutes;

    struct Config {
        string network;
        address deployer;
        address guardian;
        address relayer;
        address dispenser;
        bool enableShock;
        uint256 faucetFundWei;
        uint256 sandboxMaxSwap;
        uint256 maxPriceStaleness;
        uint8 usdgDecimals;
        uint256 faucetDailyCap;
        int256[TICKER_COUNT] prices;
    }

    struct Deployed {
        address usdg;
        address usdgFeed;
        address oracle;
        address desk;
        address registry;
        address vaultDeployer;
        address factory;
        address engine;
        address lens;
        address faucet;
        address[TICKER_COUNT] stockTokens;
        address[TICKER_COUNT] feeds;
    }

    Config internal cfg;
    Deployed internal d;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _loadConfig(vm.addr(deployerKey));

        vm.startBroadcast(deployerKey);
        _deploy();
        vm.stopBroadcast();

        if (vm.envOr("WRITE_ADDRESSES", false)) {
            _writeAddresses();
        } else {
            console2.log("WRITE_ADDRESSES is not set, deployment file not written");
        }

        console2.log("Network:", cfg.network);
        console2.log("MockUSDGV2:", d.usdg);
        console2.log("ChainlinkPriceOracleV2:", d.oracle);
        console2.log("OracleDesk:", d.desk);
        console2.log("MarketplaceRegistryV2:", d.registry);
        console2.log("VaultDeployerV2:", d.vaultDeployer);
        console2.log("StrategyFactoryV2:", d.factory);
        console2.log("RebalanceEngineV2:", d.engine);
        console2.log("StrategyLens:", d.lens);
        console2.log("FengFaucet:", d.faucet);
    }

    function _tickers() internal pure returns (string[TICKER_COUNT] memory) {
        return ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];
    }

    function _loadConfig(address deployer) internal {
        cfg.network = vm.envOr("DEPLOY_NETWORK", string("anvil"));
        cfg.deployer = deployer;
        cfg.guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        address relayer = vm.envOr("RELAYER_ADDRESS", address(0));
        address dispenser = vm.envOr("FAUCET_ADDRESS", vm.envOr("FAUCET_DISPENSER_ADDRESS", address(0)));
        if (keccak256(bytes(cfg.network)) == TESTNET_HASH) {
            if (relayer == address(0)) revert RelayerAddressRequired();
            if (relayer == deployer) revert RelayerAddressIsDeployer();
            if (dispenser == address(0)) revert FaucetAddressRequired();
            if (dispenser == deployer) revert FaucetAddressIsDeployer();
        }
        cfg.relayer = relayer == address(0) ? deployer : relayer;
        cfg.dispenser = dispenser == address(0) ? deployer : dispenser;
        cfg.enableShock = vm.envOr("ENABLE_SHOCK", uint256(0)) == 1;
        cfg.maxPriceStaleness = vm.envOr("MAX_PRICE_STALENESS", DEFAULT_MAX_PRICE_STALENESS);
        cfg.usdgDecimals = uint8(vm.envOr("USDG_DECIMALS", uint256(6)));
        cfg.faucetDailyCap = vm.envOr("FAUCET_DAILY_CAP", DEFAULT_FAUCET_DAILY_CAP);
        cfg.faucetFundWei = vm.envOr("FAUCET_ETH_FUND_WEI", cfg.faucetDailyCap * FAUCET_ETH_PER_CLAIM);
        cfg.sandboxMaxSwap =
            vm.envOr("SANDBOX_MAX_SWAP_WHOLE_USDG", DEFAULT_SANDBOX_MAX_SWAP_WHOLE_USDG) * 10 ** cfg.usdgDecimals;

        cfg.prices[0] = int256(vm.envOr("INIT_PRICE_TSLA", uint256(37162000000)));
        cfg.prices[1] = int256(vm.envOr("INIT_PRICE_AMZN", uint256(25030000000)));
        cfg.prices[2] = int256(vm.envOr("INIT_PRICE_NFLX", uint256(6707000000)));
        cfg.prices[3] = int256(vm.envOr("INIT_PRICE_PLTR", uint256(18863000000)));
        cfg.prices[4] = int256(vm.envOr("INIT_PRICE_AMD", uint256(62862000000)));
    }

    function _deploy() internal {
        string[TICKER_COUNT] memory tickers = _tickers();
        address deployer = cfg.deployer;

        MockUSDGV2 usdg = new MockUSDGV2(deployer, cfg.usdgDecimals);
        d.usdg = address(usdg);

        MockStockToken[TICKER_COUNT] memory stocks;
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            stocks[i] = new MockStockToken(string.concat("Mock ", tickers[i]), tickers[i], deployer, 1e18);
            d.stockTokens[i] = address(stocks[i]);
        }

        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            d.feeds[i] = address(
                new FengAggregator(
                    deployer,
                    FEED_DECIMALS,
                    string.concat(tickers[i], " / USD"),
                    cfg.prices[i],
                    AGGREGATOR_MAX_DEVIATION_BPS,
                    AGGREGATOR_MAX_SHOCK_BPS
                )
            );
        }
        d.usdgFeed = address(
            new FengAggregator(
                deployer,
                FEED_DECIMALS,
                "USDG / USD",
                int256(10 ** FEED_DECIMALS),
                AGGREGATOR_MAX_DEVIATION_BPS,
                AGGREGATOR_MAX_SHOCK_BPS
            )
        );

        ChainlinkPriceOracleV2 oracle = new ChainlinkPriceOracleV2(deployer);
        d.oracle = address(oracle);
        oracle.setFeed(d.usdg, d.usdgFeed);
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            oracle.setFeed(d.stockTokens[i], d.feeds[i]);
        }

        MarketplaceRegistryV2 registry = new MarketplaceRegistryV2(deployer);
        d.registry = address(registry);

        _deployDesk(stocks);

        d.vaultDeployer = address(new VaultDeployerV2());
        StrategyFactoryV2 factory = new StrategyFactoryV2(
            d.registry, d.oracle, d.desk, d.usdg, cfg.guardian, d.vaultDeployer, cfg.maxPriceStaleness
        );
        d.factory = address(factory);
        d.engine = address(new RebalanceEngineV2(d.registry));
        d.lens = address(new StrategyLens());
        registry.grantRole(registry.FACTORY_ROLE(), d.factory);

        _deployFaucet(usdg);
        _grantFeedRoles();
    }

    function _deployDesk(MockStockToken[TICKER_COUNT] memory stocks) internal {
        OracleDesk desk =
            new OracleDesk(cfg.deployer, d.usdg, d.oracle, d.registry, DESK_SPREAD_BPS, cfg.maxPriceStaleness);
        d.desk = address(desk);
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            desk.setToken(d.stockTokens[i], IOracleDesk.Mode.Mint);
            stocks[i].grantRole(stocks[i].MINTER_ROLE(), d.desk);
        }
        desk.setMaxSwapUsdg(cfg.sandboxMaxSwap);

        uint256 reserve = RESERVE_WHOLE_USDG * 10 ** cfg.usdgDecimals;
        MockUSDGV2(d.usdg).mint(cfg.deployer, reserve);
        IERC20(d.usdg).approve(d.desk, reserve);
        desk.fundReserve(reserve);
    }

    function _deployFaucet(MockUSDGV2 usdg) internal {
        FengFaucet faucet = new FengFaucet(
            cfg.deployer, d.usdg, FAUCET_ETH_PER_CLAIM, FAUCET_USDG_WHOLE * 10 ** cfg.usdgDecimals, cfg.faucetDailyCap
        );
        d.faucet = address(faucet);
        usdg.grantRole(usdg.MINTER_ROLE(), d.faucet);
        faucet.grantRole(faucet.DISPENSER_ROLE(), cfg.dispenser);
        if (cfg.faucetFundWei > 0) {
            (bool ok,) = d.faucet.call{value: cfg.faucetFundWei}("");
            if (!ok) revert FaucetFundingFailed();
        }
    }

    function _grantFeedRoles() internal {
        for (uint256 i = 0; i <= TICKER_COUNT; i++) {
            FengAggregator feed = FengAggregator(i == TICKER_COUNT ? d.usdgFeed : d.feeds[i]);
            feed.grantRole(feed.UPDATER_ROLE(), cfg.relayer);
            if (cfg.enableShock && i < TICKER_COUNT) {
                feed.grantRole(feed.SHOCK_ROLE(), cfg.relayer);
                feed.setShockEnabled(true);
            }
        }
    }

    function _networkInfo(string memory network)
        internal
        pure
        returns (string memory rpcUrl, string memory explorerUrl)
    {
        if (keccak256(bytes(network)) == keccak256(bytes("robinhood-testnet"))) {
            return ("https://rpc.testnet.chain.robinhood.com", "https://explorer.testnet.chain.robinhood.com");
        }
        return ("http://127.0.0.1:8545", "");
    }

    function _tickerMapJson(address[TICKER_COUNT] memory values) internal pure returns (string memory result) {
        string[TICKER_COUNT] memory tickers = _tickers();
        result = "{";
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            result = string.concat(result, i == 0 ? "" : ",", "\"", tickers[i], "\":\"", vm.toString(values[i]), "\"");
        }
        result = string.concat(result, "}");
    }

    function _priceOraclesJson() internal view returns (string memory result) {
        string[TICKER_COUNT] memory tickers = _tickers();
        result = "{";
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            result = string.concat(result, "\"", tickers[i], "\":\"", vm.toString(d.feeds[i]), "\",");
        }
        result = string.concat(result, "\"USDG\":\"", vm.toString(d.usdgFeed), "\"}");
    }

    function _liveJson() internal view returns (string memory) {
        string[TICKER_COUNT] memory tickers = _tickers();
        string memory tokens = "{";
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            address token = vm.envOr(string.concat("LIVE_TOKEN_", tickers[i]), address(0));
            tokens = string.concat(tokens, i == 0 ? "" : ",", "\"", tickers[i], "\":\"", vm.toString(token), "\"");
        }
        tokens = string.concat(tokens, "}");
        return string.concat(
            "{\"usdg\":\"",
            vm.toString(vm.envOr("LIVE_USDG", address(0))),
            "\",\"usdgDecimals\":6,\"stockTokens\":",
            tokens,
            ",\"strategyFactory\":\"",
            vm.toString(address(0)),
            "\",\"venue\":\"",
            vm.toString(address(0)),
            "\",\"vaults\":[]}"
        );
    }

    function _writeAddresses() internal {
        (string memory rpcUrl, string memory explorerUrl) = _networkInfo(cfg.network);
        string memory dir = string.concat("deployments/", cfg.network, "-v2");
        vm.createDir(dir, true);

        string memory head = string.concat(
            "{\n  \"schemaVersion\": 2,\n  \"chainId\": ",
            vm.toString(block.chainid),
            ",\n  \"rpcUrl\": \"",
            rpcUrl,
            "\",\n  \"explorerUrl\": \"",
            explorerUrl,
            "\",\n  \"deployedAt\": ",
            vm.toString(block.timestamp),
            ",\n  \"usdg\": \"",
            vm.toString(d.usdg),
            "\",\n  \"usdgDecimals\": ",
            vm.toString(uint256(cfg.usdgDecimals)),
            ",\n"
        );
        string memory maps = string.concat(
            "  \"stockTokens\": ",
            _tickerMapJson(d.stockTokens),
            ",\n  \"priceOracles\": ",
            _priceOraclesJson(),
            ",\n  \"oracle\": \"",
            vm.toString(d.oracle),
            "\",\n  \"venue\": \"",
            vm.toString(d.desk),
            "\",\n  \"vaultDeployer\": \"",
            vm.toString(d.vaultDeployer),
            "\",\n  \"lens\": \"",
            vm.toString(d.lens),
            "\",\n  \"faucet\": \"",
            vm.toString(d.faucet),
            "\",\n  \"guardian\": \"",
            vm.toString(cfg.guardian),
            "\",\n"
        );
        string memory tail = string.concat(
            "  \"strategyFactory\": \"",
            vm.toString(d.factory),
            "\",\n  \"rebalanceEngine\": \"",
            vm.toString(d.engine),
            "\",\n  \"marketplaceRegistry\": \"",
            vm.toString(d.registry),
            "\",\n  \"maxPriceStaleness\": ",
            vm.toString(cfg.maxPriceStaleness),
            ",\n  \"deskSpreadBps\": ",
            vm.toString(uint256(DESK_SPREAD_BPS)),
            ",\n  \"defaultMaxSlippageBps\": ",
            vm.toString(uint256(DEFAULT_MAX_SLIPPAGE_BPS)),
            ",\n  \"checkpointMinInterval\": ",
            vm.toString(CHECKPOINT_MIN_INTERVAL),
            ",\n  \"vaults\": [],\n  \"live\": ",
            _liveJson(),
            "\n}\n"
        );
        vm.writeFile(string.concat(dir, "/addresses.json"), string.concat(head, maps, tail));
    }
}
