// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Constituent} from "../contracts/interfaces/IStrategyVault.sol";
import {IMockUSDGV2} from "../contracts/v2/interfaces/IMockUSDGV2.sol";
import {IStrategyFactoryV2} from "../contracts/v2/interfaces/IStrategyFactoryV2.sol";
import {IStrategyVaultV2} from "../contracts/v2/interfaces/IStrategyVaultV2.sol";
import {StrategyMeta} from "../contracts/v2/interfaces/IMarketplaceRegistryV2.sol";
import {ISocialRegistry} from "../contracts/v2/interfaces/ISocialRegistry.sol";

contract SeedSocialV2 is Script {
    uint256 internal constant CREATOR_COUNT = 4;
    uint256 internal constant STRATEGY_COUNT = 12;
    uint16 internal constant MAX_SLIPPAGE_BPS = 100;
    uint256 internal constant CREATOR_FUND_WEI = 0.0003 ether;

    string[4] internal CREATOR_SEEDS = ["feng-seed-creator-1", "feng-seed-creator-2", "feng-seed-creator-3", "feng-seed-creator-4"];
    string[4] internal CREATOR_HANDLES = ["alex", "nova", "maya", "kai"];
    string[4] internal CREATOR_BIOS = [
        "AI & Technology Research",
        "Space, robotics and frontier tech ideas.",
        "Energy transition and grid infrastructure theses.",
        "Semiconductors and big tech systems."
    ];

    struct Spec {
        uint256 creatorIdx;
        string name;
        string symbol;
        string description;
        string category;
        string tagB;
        uint16 maxWeightBps;
        uint256 interval;
        uint256 seedWhole;
        Constituent[] constituents;
    }

    IStrategyFactoryV2 internal factory;
    ISocialRegistry internal social;
    address internal usdg;
    uint256 internal usdgUnit;

    mapping(string => address) internal stock;
    uint256[CREATOR_COUNT] internal creatorKeys;
    address[CREATOR_COUNT] internal creatorAddrs;

    address[STRATEGY_COUNT] internal vaults;
    address[STRATEGY_COUNT] internal tokens;
    string[STRATEGY_COUNT] internal symbols;
    string[STRATEGY_COUNT] internal names;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        string memory network = vm.envOr("DEPLOY_NETWORK", string("robinhood-testnet"));
        string memory path = string.concat("deployments/", network, "-v2/addresses.json");

        _loadAddresses(path);
        _deriveCreators();

        vm.startBroadcast(deployerKey);
        _fundCreators();
        _mintUsdgToCreators();
        vm.stopBroadcast();

        _setProfiles();
        _createStrategies();
        _followSome();

        if (vm.envOr("WRITE_ADDRESSES", false)) {
            string memory existingJson = vm.readFile(path);
            try vm.parseJsonStringArray(existingJson, ".vaults[*].symbol") returns (string[] memory existingSymbols) {
                require(existingSymbols.length == 0, "refusing to overwrite non-empty .vaults; merge manually");
            } catch {}
            vm.writeJson(_vaultsJson(), path, ".vaults");
        } else {
            console2.log("WRITE_ADDRESSES is not set, deployment file not updated");
        }

        for (uint256 i = 0; i < STRATEGY_COUNT; i++) {
            console2.log(symbols[i], vaults[i]);
        }
    }

    function _loadAddresses(string memory path) internal {
        string memory json = vm.readFile(path);
        factory = IStrategyFactoryV2(vm.parseJsonAddress(json, ".strategyFactory"));
        social = ISocialRegistry(vm.parseJsonAddress(json, ".socialRegistry"));
        usdg = vm.parseJsonAddress(json, ".usdg");
        usdgUnit = 10 ** IERC20Metadata(usdg).decimals();

        string[13] memory tickers =
            ["TSLA", "AMZN", "NFLX", "PLTR", "AMD", "NVDA", "TSMC", "MSFT", "GOOGL", "RKLB", "ISRG", "XOM", "ENPH"];
        for (uint256 i = 0; i < tickers.length; i++) {
            stock[tickers[i]] = vm.parseJsonAddress(json, string.concat(".stockTokens.", tickers[i]));
        }
    }

    function _deriveCreators() internal {
        for (uint256 i = 0; i < CREATOR_COUNT; i++) {
            uint256 pk = uint256(keccak256(bytes(CREATOR_SEEDS[i])));
            creatorKeys[i] = pk;
            creatorAddrs[i] = vm.addr(pk);
        }
    }

    function _fundCreators() internal {
        for (uint256 i = 0; i < CREATOR_COUNT; i++) {
            (bool ok,) = creatorAddrs[i].call{value: CREATOR_FUND_WEI}("");
            require(ok, "fund creator failed");
        }
    }

    function _mintUsdgToCreators() internal {
        for (uint256 i = 0; i < CREATOR_COUNT; i++) {
            IMockUSDGV2(usdg).mint(creatorAddrs[i], 6000 * usdgUnit);
        }
    }

    function _setProfiles() internal {
        for (uint256 i = 0; i < CREATOR_COUNT; i++) {
            vm.broadcast(creatorKeys[i]);
            social.setProfile(CREATOR_HANDLES[i], CREATOR_BIOS[i]);
        }
    }

    function _createStrategies() internal {
        Spec[STRATEGY_COUNT] memory specs = _specs();
        for (uint256 i = 0; i < STRATEGY_COUNT; i++) {
            _create(i, specs[i]);
        }
    }

    function _create(uint256 index, Spec memory s) internal {
        StrategyMeta memory meta = _meta(s);
        uint256 pk = creatorKeys[s.creatorIdx];

        vm.startBroadcast(pk);
        (address vault, address token) =
            factory.createStrategy(s.name, s.symbol, s.constituents, s.maxWeightBps, s.interval, MAX_SLIPPAGE_BPS, meta);

        uint256 amount = s.seedWhole * usdgUnit;
        IERC20(usdg).approve(vault, amount);
        uint256 minShares = IStrategyVaultV2(vault).previewDeposit(amount) * 99 / 100;
        IStrategyVaultV2(vault).deposit(amount, creatorAddrs[s.creatorIdx], minShares);
        vm.stopBroadcast();

        vaults[index] = vault;
        tokens[index] = token;
        symbols[index] = s.symbol;
        names[index] = s.name;
    }

    function _followSome() internal {
        vm.broadcast(creatorKeys[0]);
        social.follow(creatorAddrs[1]);
        vm.broadcast(creatorKeys[0]);
        social.follow(creatorAddrs[2]);
        vm.broadcast(creatorKeys[0]);
        social.follow(creatorAddrs[3]);

        vm.broadcast(creatorKeys[1]);
        social.follow(vaults[0]);
        vm.broadcast(creatorKeys[1]);
        social.follow(vaults[6]);

        vm.broadcast(creatorKeys[2]);
        social.follow(vaults[1]);
        vm.broadcast(creatorKeys[2]);
        social.follow(vaults[9]);

        vm.broadcast(creatorKeys[3]);
        social.follow(vaults[4]);
        vm.broadcast(creatorKeys[3]);
        social.follow(vaults[0]);
    }

    function _meta(Spec memory s) internal pure returns (StrategyMeta memory meta) {
        require(bytes(s.description).length <= 160, "description too long");
        string[] memory tags = new string[](2);
        tags[0] = s.category;
        tags[1] = s.tagB;
        meta = StrategyMeta({description: s.description, tags: tags});
    }

    function _vaultsJson() internal view returns (string memory result) {
        result = "[";
        for (uint256 i = 0; i < STRATEGY_COUNT; i++) {
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
                "\",\"universe\":\"sandbox\",\"depth\":",
                vm.toString(uint256(IStrategyVaultV2(vaults[i]).depth())),
                "}"
            );
        }
        result = string.concat(result, "]");
    }

    function _c(string memory ticker, uint16 w) internal view returns (Constituent memory) {
        return Constituent({token: stock[ticker], targetWeightBps: w, isStrategyToken: false});
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

    function _two(Constituent memory a, Constituent memory b) internal pure returns (Constituent[] memory list) {
        list = new Constituent[](2);
        list[0] = a;
        list[1] = b;
    }

    function _four(Constituent memory a, Constituent memory b, Constituent memory c, Constituent memory d)
        internal
        pure
        returns (Constituent[] memory list)
    {
        list = new Constituent[](4);
        list[0] = a;
        list[1] = b;
        list[2] = c;
        list[3] = d;
    }

    function _specs() internal view returns (Spec[STRATEGY_COUNT] memory s) {
        s[0] = Spec({
            creatorIdx: 0,
            name: "AI Will Win",
            symbol: "AIWIN",
            description: "AI will dominate the next decade: Nvidia, AMD, TSMC and Microsoft power the buildout.",
            category: "ai",
            tagB: "buildout",
            maxWeightBps: 4000,
            interval: 7 days,
            seedWhole: 1500,
            constituents: _four(_c("NVDA", 4000), _c("AMD", 2500), _c("TSMC", 2000), _c("MSFT", 1500))
        });
        s[1] = Spec({
            creatorIdx: 0,
            name: "Semiconductor Boom",
            symbol: "CHIPS",
            description: "The chip supercycle isn't over: TSMC, AMD and Nvidia lead the next leg of semiconductor demand.",
            category: "semiconductors",
            tagB: "supercycle",
            maxWeightBps: 3500,
            interval: 7 days,
            seedWhole: 1200,
            constituents: _three(_c("TSMC", 3500), _c("AMD", 3500), _c("NVDA", 3000))
        });
        s[2] = Spec({
            creatorIdx: 0,
            name: "Cloud Titans",
            symbol: "CLOUD",
            description: "Big tech's cloud moat compounds: Microsoft, Google and Amazon keep winning enterprise workloads.",
            category: "technology",
            tagB: "cloud",
            maxWeightBps: 4000,
            interval: 7 days,
            seedWhole: 1000,
            constituents: _three(_c("MSFT", 4000), _c("GOOGL", 3500), _c("AMZN", 2500))
        });
        s[3] = Spec({
            creatorIdx: 1,
            name: "Robotics Future",
            symbol: "ROBOT",
            description: "Robots are leaving factories for hospitals and homes: Intuitive Surgical, Nvidia and Rocket Lab.",
            category: "robotics",
            tagB: "automation",
            maxWeightBps: 4000,
            interval: 7 days,
            seedWhole: 900,
            constituents: _three(_c("ISRG", 4000), _c("NVDA", 3000), _c("RKLB", 3000))
        });
        s[4] = Spec({
            creatorIdx: 1,
            name: "Space Race",
            symbol: "ORBIT",
            description: "Launch costs keep falling and demand keeps rising: Rocket Lab, Intuitive Surgical and Google.",
            category: "space",
            tagB: "launch",
            maxWeightBps: 5000,
            interval: 7 days,
            seedWhole: 800,
            constituents: _three(_c("RKLB", 5000), _c("ISRG", 2500), _c("GOOGL", 2500))
        });
        s[5] = Spec({
            creatorIdx: 1,
            name: "Deep Space Capital",
            symbol: "COSMOS",
            description: "Space infrastructure needs power on the ground too: Rocket Lab, Exxon and Enphase, diversified.",
            category: "space",
            tagB: "infra",
            maxWeightBps: 6000,
            interval: 7 days,
            seedWhole: 700,
            constituents: _three(_c("RKLB", 6000), _c("XOM", 2000), _c("ENPH", 2000))
        });
        s[6] = Spec({
            creatorIdx: 2,
            name: "Clean Energy Shift",
            symbol: "GREEN",
            description: "The grid is going electric: Enphase, Exxon and Tesla fund the messy, profitable transition.",
            category: "energy",
            tagB: "transition",
            maxWeightBps: 4500,
            interval: 7 days,
            seedWhole: 1100,
            constituents: _three(_c("ENPH", 4500), _c("XOM", 2500), _c("TSLA", 3000))
        });
        s[7] = Spec({
            creatorIdx: 2,
            name: "Energy Barbell",
            symbol: "BARBL",
            description: "A barbell on energy: half legacy oil in Exxon, half the solar upside in Enphase.",
            category: "energy",
            tagB: "barbell",
            maxWeightBps: 5000,
            interval: 7 days,
            seedWhole: 850,
            constituents: _two(_c("XOM", 5000), _c("ENPH", 5000))
        });
        s[8] = Spec({
            creatorIdx: 2,
            name: "Grid Future",
            symbol: "VOLT",
            description: "Electrification needs smarter grids: Enphase, Exxon and Microsoft's data-center power demand.",
            category: "energy",
            tagB: "grid",
            maxWeightBps: 4000,
            interval: 7 days,
            seedWhole: 750,
            constituents: _three(_c("ENPH", 4000), _c("XOM", 3000), _c("MSFT", 3000))
        });
        s[9] = Spec({
            creatorIdx: 3,
            name: "Chip Supercycle",
            symbol: "SUPER",
            description: "Chips are the new oil: TSMC's foundry lead, Nvidia's compute and AMD's catch-up trade.",
            category: "semiconductors",
            tagB: "foundry",
            maxWeightBps: 4500,
            interval: 7 days,
            seedWhole: 950,
            constituents: _three(_c("TSMC", 4500), _c("NVDA", 3500), _c("AMD", 2000))
        });
        s[10] = Spec({
            creatorIdx: 3,
            name: "Big Tech Core",
            symbol: "BIGT",
            description: "Core big tech, no heroics: Microsoft, Google and Amazon as the default growth allocation.",
            category: "technology",
            tagB: "core",
            maxWeightBps: 3500,
            interval: 7 days,
            seedWhole: 1050,
            constituents: _three(_c("MSFT", 3500), _c("GOOGL", 3500), _c("AMZN", 3000))
        });
        s[11] = Spec({
            creatorIdx: 3,
            name: "Humanoid Robotics",
            symbol: "ANDRO",
            description: "Humanoid robots are a decade away, not a century: Intuitive Surgical, Rocket Lab and Nvidia.",
            category: "robotics",
            tagB: "humanoid",
            maxWeightBps: 5000,
            interval: 7 days,
            seedWhole: 650,
            constituents: _three(_c("ISRG", 5000), _c("RKLB", 2500), _c("NVDA", 2500))
        });
    }
}
