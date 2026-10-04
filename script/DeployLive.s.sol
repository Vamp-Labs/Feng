// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {ChainlinkPriceOracleV2} from "../contracts/v2/oracle/ChainlinkPriceOracleV2.sol";
import {OracleDesk} from "../contracts/v2/venue/OracleDesk.sol";
import {IOracleDesk} from "../contracts/v2/interfaces/IOracleDesk.sol";
import {MarketplaceRegistryV2} from "../contracts/v2/MarketplaceRegistryV2.sol";
import {StrategyFactoryV2} from "../contracts/v2/StrategyFactoryV2.sol";

interface IScaledStock {
    function uiMultiplier() external view returns (uint256);
    function paused() external view returns (bool);
}

interface IPausableUsdg {
    function paused() external view returns (bool);
}

contract DeployLive is Script {
    uint256 internal constant TICKER_COUNT = 5;
    uint256 internal constant BPS = 10_000;
    uint16 internal constant DESK_SPREAD_BPS = 10;
    uint8 internal constant LIVE_USDG_DECIMALS = 6;
    uint256 internal constant UI_MULTIPLIER_ONE = 1e18;
    uint256 internal constant DEFAULT_MAX_SWAP_WHOLE_USDG = 25;
    uint256 internal constant DEFAULT_DESK_USDG_BPS = 3000;
    uint256 internal constant DEFAULT_DESK_STOCK_BPS = 7000;

    struct Config {
        string network;
        string path;
        address deployer;
        address guardian;
        address usdg;
        address oracle;
        address registry;
        address vaultDeployer;
        uint256 maxPriceStaleness;
        uint256 maxSwapUsdg;
        uint256 deskUsdgBps;
        uint256 deskStockBps;
        address[TICKER_COUNT] stocks;
        address[TICKER_COUNT] feeds;
    }

    Config internal cfg;
    address internal desk;
    address internal factory;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        _loadConfig(vm.addr(deployerKey));
        _preflight();

        uint256 usdgBalance = IERC20(cfg.usdg).balanceOf(cfg.deployer);
        uint256[TICKER_COUNT] memory stockBalances;
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            stockBalances[i] = IERC20(cfg.stocks[i]).balanceOf(cfg.deployer);
        }
        uint256 deskUsdg = usdgBalance * cfg.deskUsdgBps / BPS;

        vm.startBroadcast(deployerKey);
        _deploy();
        _fundDesk(deskUsdg, stockBalances);
        vm.stopBroadcast();

        if (vm.envOr("WRITE_ADDRESSES", false)) {
            _writeLive();
        } else {
            console2.log("WRITE_ADDRESSES is not set, deployment file not updated");
        }

        console2.log("Live OracleDesk:", desk);
        console2.log("Live StrategyFactoryV2:", factory);
        console2.log("Deployer USDG balance (units):", usdgBalance);
        console2.log("Desk reserve funded (units):", deskUsdg);
        console2.log("maxSwapUsdg (units):", cfg.maxSwapUsdg);
    }

    function _tickers() internal pure returns (string[TICKER_COUNT] memory) {
        return ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];
    }

    function _loadConfig(address deployer) internal {
        cfg.network = vm.envOr("DEPLOY_NETWORK", string("robinhood-testnet"));
        cfg.path = string.concat("deployments/", cfg.network, "-v2/addresses.json");
        string memory json = vm.readFile(cfg.path);
        cfg.deployer = deployer;
        cfg.guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        cfg.usdg = vm.envAddress("LIVE_USDG");
        cfg.oracle = vm.parseJsonAddress(json, ".oracle");
        cfg.registry = vm.parseJsonAddress(json, ".marketplaceRegistry");
        cfg.vaultDeployer = vm.parseJsonAddress(json, ".vaultDeployer");
        cfg.maxPriceStaleness = vm.parseJsonUint(json, ".maxPriceStaleness");
        cfg.deskUsdgBps = vm.envOr("LIVE_DESK_USDG_BPS", DEFAULT_DESK_USDG_BPS);
        cfg.deskStockBps = vm.envOr("LIVE_DESK_STOCK_BPS", DEFAULT_DESK_STOCK_BPS);
        require(cfg.deskUsdgBps <= BPS && cfg.deskStockBps <= BPS, "DeployLive: desk bps above 10000");

        string[TICKER_COUNT] memory tickers = _tickers();
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            cfg.stocks[i] = vm.envAddress(string.concat("LIVE_TOKEN_", tickers[i]));
            cfg.feeds[i] = vm.parseJsonAddress(json, string.concat(".priceOracles.", tickers[i]));
        }
        cfg.maxSwapUsdg = vm.envOr("LIVE_MAX_SWAP_USDG", DEFAULT_MAX_SWAP_WHOLE_USDG) * 10 ** LIVE_USDG_DECIMALS;

        address existing = vm.parseJsonAddress(json, ".live.strategyFactory");
        require(
            existing == address(0) || existing.code.length == 0,
            "DeployLive: live.strategyFactory already deployed, refusing a second Live set"
        );
    }

    function _preflight() internal view {
        string[TICKER_COUNT] memory tickers = _tickers();
        require(cfg.usdg.code.length != 0, "DeployLive: LIVE_USDG has no code on this chain (use a fork of testnet)");
        require(IERC20Metadata(cfg.usdg).decimals() == LIVE_USDG_DECIMALS, "DeployLive: real USDG decimals is not 6");
        require(!IPausableUsdg(cfg.usdg).paused(), "DeployLive: real USDG is paused");
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            address token = cfg.stocks[i];
            require(token.code.length != 0, string.concat("DeployLive: no code for ", tickers[i]));
            require(
                IScaledStock(token).uiMultiplier() == UI_MULTIPLIER_ONE,
                string.concat("DeployLive: uiMultiplier is not 1e18 for ", tickers[i])
            );
            require(IERC20Metadata(token).decimals() <= 18, string.concat("DeployLive: decimals above 18 ", tickers[i]));
            require(!IScaledStock(token).paused(), string.concat("DeployLive: token paused ", tickers[i]));
            require(cfg.feeds[i].code.length != 0, string.concat("DeployLive: sandbox feed missing ", tickers[i]));
        }
        require(Ownable(cfg.oracle).owner() == cfg.deployer, "DeployLive: deployer does not own the shared oracle");
        require(
            AccessControl(cfg.registry).hasRole(0x00, cfg.deployer),
            "DeployLive: deployer is not registry admin, cannot grant FACTORY_ROLE"
        );
    }

    function _deploy() internal {
        ChainlinkPriceOracleV2 oracle = ChainlinkPriceOracleV2(cfg.oracle);
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            oracle.setFeed(cfg.stocks[i], cfg.feeds[i]);
        }

        OracleDesk liveDesk =
            new OracleDesk(cfg.deployer, cfg.usdg, cfg.oracle, cfg.registry, DESK_SPREAD_BPS, cfg.maxPriceStaleness);
        desk = address(liveDesk);
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            liveDesk.setToken(cfg.stocks[i], IOracleDesk.Mode.Inventory);
        }
        liveDesk.setMaxSwapUsdg(cfg.maxSwapUsdg);

        StrategyFactoryV2 liveFactory = new StrategyFactoryV2(
            cfg.registry, cfg.oracle, desk, cfg.usdg, cfg.guardian, cfg.vaultDeployer, cfg.maxPriceStaleness
        );
        factory = address(liveFactory);
        MarketplaceRegistryV2 registry = MarketplaceRegistryV2(cfg.registry);
        registry.grantRole(registry.FACTORY_ROLE(), factory);
    }

    function _fundDesk(uint256 deskUsdg, uint256[TICKER_COUNT] memory stockBalances) internal {
        OracleDesk liveDesk = OracleDesk(desk);
        if (deskUsdg > 0) {
            IERC20(cfg.usdg).approve(desk, deskUsdg);
            liveDesk.fundReserve(deskUsdg);
        } else {
            console2.log("Deployer holds no real USDG: desk reserve NOT funded");
        }
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            uint256 amount = stockBalances[i] * cfg.deskStockBps / BPS;
            if (amount == 0) {
                console2.log("Deployer holds no real token at index, desk inventory NOT funded:", i);
                continue;
            }
            IERC20(cfg.stocks[i]).approve(desk, amount);
            liveDesk.fundInventory(cfg.stocks[i], amount);
        }
    }

    function _writeLive() internal {
        string[TICKER_COUNT] memory tickers = _tickers();
        string memory tokens = "{";
        for (uint256 i = 0; i < TICKER_COUNT; i++) {
            tokens =
                string.concat(tokens, i == 0 ? "" : ",", "\"", tickers[i], "\":\"", vm.toString(cfg.stocks[i]), "\"");
        }
        tokens = string.concat(tokens, "}");
        string memory live = string.concat(
            "{\"usdg\":\"",
            vm.toString(cfg.usdg),
            "\",\"usdgDecimals\":",
            vm.toString(uint256(LIVE_USDG_DECIMALS)),
            ",\"stockTokens\":",
            tokens,
            ",\"strategyFactory\":\"",
            vm.toString(factory),
            "\",\"venue\":\"",
            vm.toString(desk),
            "\",\"maxSwapUsdg\":",
            vm.toString(cfg.maxSwapUsdg),
            ",\"deskSpreadBps\":",
            vm.toString(uint256(DESK_SPREAD_BPS)),
            ",\"vaults\":[]}"
        );
        vm.writeJson(live, cfg.path, ".live");
    }
}
