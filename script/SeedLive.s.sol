// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constituent} from "../contracts/interfaces/IStrategyVault.sol";
import {IPriceOracle} from "../contracts/interfaces/IPriceOracle.sol";
import {IOracleDesk} from "../contracts/v2/interfaces/IOracleDesk.sol";
import {IStrategyFactoryV2} from "../contracts/v2/interfaces/IStrategyFactoryV2.sol";
import {IStrategyVaultV2} from "../contracts/v2/interfaces/IStrategyVaultV2.sol";
import {StrategyMeta} from "../contracts/v2/interfaces/IMarketplaceRegistryV2.sol";

interface ILiveDesk {
    function maxSwapUsdg() external view returns (uint256);
}

interface IPausableUsdg {
    function paused() external view returns (bool);
}

contract SeedLive is Script {
    uint256 internal constant TSLA = 0;
    uint256 internal constant AMZN = 1;
    uint256 internal constant NFLX = 2;
    uint256 internal constant PLTR = 3;
    uint256 internal constant AMD = 4;
    uint256 internal constant STOCKS = 5;
    uint256 internal constant COUNT = 3;
    uint256 internal constant BPS = 10_000;
    uint16 internal constant MAX_SLIPPAGE_BPS = 100;
    uint256 internal constant REBALANCE_INTERVAL = 7 days;
    uint256 internal constant DEFAULT_MIN_BUDGET_WHOLE = 15;
    uint256 internal constant INVENTORY_MARGIN_BPS = 10_100;

    uint256 internal constant SHARE_AI_BPS = 3500;
    uint256 internal constant SHARE_FIVE_BPS = 3500;
    uint256 internal constant SHARE_CORE_BPS = 3000;
    uint256 internal constant LEG_AI_BPS = 4000;
    uint256 internal constant LEG_FIVE_BPS = 2000;
    uint256 internal constant LEG_CORE_BPS = 2000;

    IStrategyFactoryV2 internal factory;
    IOracleDesk internal desk;
    address internal usdg;
    address internal oracle;
    address internal seedReceiver;
    address[STOCKS] internal stocks;
    address[COUNT] internal vaults;
    address[COUNT] internal tokens;
    string[COUNT] internal symbols;
    string[COUNT] internal names;
    uint256[COUNT] internal amounts;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        string memory network = vm.envOr("DEPLOY_NETWORK", string("robinhood-testnet"));
        string memory path = string.concat("deployments/", network, "-v2/addresses.json");

        seedReceiver = deployer;
        _loadAddresses(path);
        _plan(deployer);

        vm.startBroadcast(deployerKey);
        _create(0, _ai());
        _create(1, _five());
        _create(2, _core());
        vm.stopBroadcast();

        if (vm.envOr("WRITE_ADDRESSES", false)) {
            vm.writeJson(_vaultsJson(), path, ".live.vaults");
        } else {
            console2.log("WRITE_ADDRESSES is not set, deployment file not updated");
        }

        for (uint256 i = 0; i < COUNT; i++) {
            console2.log(symbols[i], vaults[i]);
        }
    }

    function _loadAddresses(string memory path) internal {
        string memory json = vm.readFile(path);
        require(
            !vm.keyExists(json, ".live.vaults[0]"), "SeedLive: live.vaults is not empty, refusing to seed a second set"
        );
        factory = IStrategyFactoryV2(vm.parseJsonAddress(json, ".live.strategyFactory"));
        require(address(factory).code.length != 0, "SeedLive: live.strategyFactory has no code, run DeployLive first");
        desk = IOracleDesk(vm.parseJsonAddress(json, ".live.venue"));
        usdg = vm.parseJsonAddress(json, ".live.usdg");
        oracle = vm.parseJsonAddress(json, ".oracle");
        string[STOCKS] memory tickers = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];
        for (uint256 i = 0; i < STOCKS; i++) {
            stocks[i] = vm.parseJsonAddress(json, string.concat(".live.stockTokens.", tickers[i]));
        }
    }

    function _plan(address deployer) internal {
        require(!IPausableUsdg(usdg).paused(), "SeedLive: real USDG is paused");
        uint256 decimals = IERC20Metadata(usdg).decimals();
        uint256 balance = IERC20(usdg).balanceOf(deployer);
        uint256 minBudget = vm.envOr("LIVE_MIN_SEED_USDG", DEFAULT_MIN_BUDGET_WHOLE) * 10 ** decimals;
        uint256 budgetBps = vm.envOr("LIVE_SEED_BPS", BPS);
        require(budgetBps != 0 && budgetBps <= BPS, "SeedLive: LIVE_SEED_BPS must be in 1..10000");
        uint256 budget = balance * budgetBps / BPS;
        if (budget < minBudget) {
            console2.log("SeedLive ABORT: deployer real USDG balance (units):", balance);
            console2.log("SeedLive ABORT: seed budget (units):", budget);
            console2.log("SeedLive ABORT: minimum required (units):", minBudget);
            revert(
                "SeedLive: deployer real USDG is below the minimum. Claim USDG at https://faucet.paxos.com, then retry"
            );
        }

        uint256 cap = ILiveDesk(address(desk)).maxSwapUsdg();
        amounts[0] = _capped(budget * SHARE_AI_BPS / BPS, LEG_AI_BPS, cap);
        amounts[1] = _capped(budget * SHARE_FIVE_BPS / BPS, LEG_FIVE_BPS, cap);
        amounts[2] = _capped(budget * SHARE_CORE_BPS / BPS, LEG_CORE_BPS, cap);

        _checkOracle();
        _checkInventory();

        console2.log("Seed plan (USDG units): LIVE-AI", amounts[0]);
        console2.log("Seed plan (USDG units): LIVE-5", amounts[1]);
        console2.log("Seed plan (USDG units): LIVE-CORE", amounts[2]);
        console2.log("Total (USDG units)", amounts[0] + amounts[1] + amounts[2]);
    }

    function _capped(uint256 amount, uint256 legBps, uint256 cap) internal pure returns (uint256) {
        if (cap == 0) return amount;
        uint256 maxAmount = cap * BPS / legBps;
        return amount > maxAmount ? maxAmount : amount;
    }

    function _checkOracle() internal view {
        uint256 staleness = desk.maxPriceStaleness();
        for (uint256 i = 0; i < STOCKS; i++) {
            (uint256 price, uint256 updatedAt) = IPriceOracle(oracle).getPrice(stocks[i]);
            require(price != 0, "SeedLive: zero price, check the shared feed");
            require(
                block.timestamp <= updatedAt + staleness,
                "SeedLive: shared price feed is stale, run the relayer or refresh() the feed before seeding"
            );
        }
    }

    function _weights() internal pure returns (uint256[STOCKS][COUNT] memory w) {
        w[0] = [uint256(0), 2500, 0, 4000, 3500];
        w[1] = [uint256(2000), 2000, 2000, 2000, 2000];
        w[2] = [uint256(2800), 1800, 800, 2400, 2200];
    }

    function _checkInventory() internal view {
        uint256[STOCKS][COUNT] memory w = _weights();
        uint256 spread = desk.spreadBps();
        uint256 decimals = IERC20Metadata(usdg).decimals();
        for (uint256 i = 0; i < STOCKS; i++) {
            uint256 usdgNeed;
            for (uint256 s = 0; s < COUNT; s++) {
                usdgNeed += amounts[s] * w[s][i] / BPS;
            }
            (uint256 price,) = IPriceOracle(oracle).getPrice(stocks[i]);
            uint256 buyPrice = Math.mulDiv(price, BPS + spread, BPS, Math.Rounding.Ceil);
            uint256 unit = 10 ** (uint256(desk.tokenDecimals(stocks[i])) + 18 - decimals);
            uint256 tokensNeed = Math.mulDiv(usdgNeed, unit, buyPrice) * INVENTORY_MARGIN_BPS / BPS;
            uint256 inventory = desk.tokenInventory(stocks[i]);
            if (inventory < tokensNeed) {
                console2.log("SeedLive ABORT: desk inventory of token index (0 TSLA 1 AMZN 2 NFLX 3 PLTR 4 AMD):", i);
                console2.log("SeedLive ABORT: desk holds (token units):", inventory);
                console2.log("SeedLive ABORT: seed needs about (token units):", tokensNeed);
                revert("SeedLive: desk inventory too low. Fund it with fundInventory or lower LIVE_SEED_BPS");
            }
        }
    }

    function _create(uint256 index, Spec memory s) internal {
        (address vault, address token) = factory.createStrategy(
            s.name, s.symbol, s.constituents, s.maxWeightBps, REBALANCE_INTERVAL, MAX_SLIPPAGE_BPS, _meta(s)
        );
        vaults[index] = vault;
        tokens[index] = token;
        symbols[index] = s.symbol;
        names[index] = s.name;

        IERC20(usdg).approve(vault, amounts[index]);
        uint256 minShares = IStrategyVaultV2(vault).previewDeposit(amounts[index]) * 99 / 100;
        IStrategyVaultV2(vault).deposit(amounts[index], seedReceiver, minShares);
    }

    struct Spec {
        string name;
        string symbol;
        string description;
        string tagA;
        string tagB;
        uint16 maxWeightBps;
        Constituent[] constituents;
    }

    function _meta(Spec memory s) internal pure returns (StrategyMeta memory meta) {
        require(bytes(s.description).length <= 160, "description too long");
        string[] memory tags = new string[](2);
        tags[0] = s.tagA;
        tags[1] = s.tagB;
        meta = StrategyMeta({description: s.description, tags: tags});
    }

    function _vaultsJson() internal view returns (string memory result) {
        result = "[";
        for (uint256 i = 0; i < COUNT; i++) {
            result = string.concat(
                result,
                i == 0 ? "" : ",",
                "{\"symbol\":\"",
                symbols[i],
                "\",\"name\":\"",
                names[i],
                "\",\"vault\":\"",
                vm.toString(vaults[i]),
                "\",\"token\":\"",
                vm.toString(tokens[i]),
                "\",\"universe\":\"live\",\"depth\":",
                vm.toString(uint256(IStrategyVaultV2(vaults[i]).depth())),
                "}"
            );
        }
        result = string.concat(result, "]");
    }

    function _ai() internal view returns (Spec memory) {
        Constituent[] memory cs = new Constituent[](3);
        cs[0] = _s(PLTR, 4000);
        cs[1] = _s(AMD, 3500);
        cs[2] = _s(AMZN, 2500);
        return Spec({
            name: "Live AI Growth",
            symbol: "LIVE-AI",
            description: "Real Robinhood testnet stock tokens: Palantir, AMD and Amazon, rebalanced weekly.",
            tagA: "live",
            tagB: "ai",
            maxWeightBps: 4000,
            constituents: cs
        });
    }

    function _five() internal view returns (Spec memory) {
        Constituent[] memory cs = new Constituent[](5);
        cs[0] = _s(TSLA, 2000);
        cs[1] = _s(AMZN, 2000);
        cs[2] = _s(NFLX, 2000);
        cs[3] = _s(PLTR, 2000);
        cs[4] = _s(AMD, 2000);
        return Spec({
            name: "Live Big Five Equal",
            symbol: "LIVE-5",
            description: "Equal weight across the five real Robinhood testnet stock tokens, rebalanced weekly.",
            tagA: "live",
            tagB: "index",
            maxWeightBps: 2000,
            constituents: cs
        });
    }

    function _core() internal view returns (Spec memory) {
        Constituent[] memory cs = new Constituent[](3);
        cs[0] = Constituent({token: tokens[0], targetWeightBps: 4000, isStrategyToken: true});
        cs[1] = Constituent({token: tokens[1], targetWeightBps: 4000, isStrategyToken: true});
        cs[2] = _s(TSLA, 2000);
        return Spec({
            name: "Live Core Satellite",
            symbol: "LIVE-CORE",
            description: "Composed live strategy: Live AI Growth and Live Big Five Equal plus a Tesla satellite.",
            tagA: "live",
            tagB: "composed",
            maxWeightBps: 4000,
            constituents: cs
        });
    }

    function _s(uint256 stock, uint16 weightBps) internal view returns (Constituent memory) {
        return Constituent({token: stocks[stock], targetWeightBps: weightBps, isStrategyToken: false});
    }
}
