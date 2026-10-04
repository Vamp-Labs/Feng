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

contract SeedV2 is Script {
    uint256 internal constant TSLA = 0;
    uint256 internal constant AMZN = 1;
    uint256 internal constant NFLX = 2;
    uint256 internal constant PLTR = 3;
    uint256 internal constant AMD = 4;
    uint256 internal constant COUNT = 10;
    uint16 internal constant MAX_SLIPPAGE_BPS = 100;
    uint256 internal constant MAX_DESCRIPTION_BYTES = 160;
    uint256 internal constant MAX_TAGS = 3;
    uint256 internal constant MAX_TAG_BYTES = 16;

    struct Spec {
        string name;
        string symbol;
        string description;
        string tagA;
        string tagB;
        uint16 maxWeightBps;
        uint256 interval;
        uint256 seedWhole;
        Constituent[] constituents;
    }

    IStrategyFactoryV2 internal factory;
    address internal usdg;
    address internal seedReceiver;
    address[5] internal stocks;
    address[COUNT] internal vaults;
    address[COUNT] internal tokens;
    string[COUNT] internal symbols;
    string[COUNT] internal names;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        string memory network = vm.envOr("DEPLOY_NETWORK", string("robinhood-testnet"));
        string memory path = string.concat("deployments/", network, "-v2/addresses.json");

        seedReceiver = deployer;
        _loadAddresses(path);

        vm.startBroadcast(deployerKey);
        _seed(deployer);
        vm.stopBroadcast();

        if (vm.envOr("WRITE_ADDRESSES", false)) {
            vm.writeJson(_vaultsJson(), path, ".vaults");
        } else {
            console2.log("WRITE_ADDRESSES is not set, deployment file not updated");
        }

        for (uint256 i = 0; i < COUNT; i++) {
            console2.log(symbols[i], vaults[i]);
        }
    }

    function _loadAddresses(string memory path) internal {
        string memory json = vm.readFile(path);
        factory = IStrategyFactoryV2(vm.parseJsonAddress(json, ".strategyFactory"));
        usdg = vm.parseJsonAddress(json, ".usdg");
        string[5] memory tickers = ["TSLA", "AMZN", "NFLX", "PLTR", "AMD"];
        for (uint256 i = 0; i < 5; i++) {
            stocks[i] = vm.parseJsonAddress(json, string.concat(".stockTokens.", tickers[i]));
        }
    }

    function _seed(address deployer) internal {
        uint256 unit = 10 ** IERC20Metadata(usdg).decimals();
        IMockUSDGV2(usdg).mint(deployer, 26_200 * unit);

        _create(0, _aigr());
        _create(1, _strm());
        _create(2, _evmo());
        _create(3, _eq5());
        _create(4, _defc());
        _create(5, _chip());
        _create(6, _bltz());
        _create(7, _clcm());
        _create(8, _core());
        _create(9, _conv());
    }

    function _create(uint256 index, Spec memory s) internal {
        StrategyMeta memory meta = _meta(s);
        (address vault, address token) =
            factory.createStrategy(s.name, s.symbol, s.constituents, s.maxWeightBps, s.interval, MAX_SLIPPAGE_BPS, meta);
        vaults[index] = vault;
        tokens[index] = token;
        symbols[index] = s.symbol;
        names[index] = s.name;

        uint256 amount = s.seedWhole * 10 ** IERC20Metadata(usdg).decimals();
        IERC20(usdg).approve(vault, amount);
        uint256 minShares = IStrategyVaultV2(vault).previewDeposit(amount) * 99 / 100;
        IStrategyVaultV2(vault).deposit(amount, seedReceiver, minShares);
    }

    function _meta(Spec memory s) internal pure returns (StrategyMeta memory meta) {
        require(bytes(s.description).length <= MAX_DESCRIPTION_BYTES, "description too long");
        string[] memory tags = new string[](2);
        tags[0] = s.tagA;
        tags[1] = s.tagB;
        require(tags.length <= MAX_TAGS, "too many tags");
        for (uint256 i = 0; i < tags.length; i++) {
            uint256 len = bytes(tags[i]).length;
            require(len > 0 && len <= MAX_TAG_BYTES, "bad tag length");
        }
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
                "\",\"universe\":\"sandbox\",\"depth\":",
                vm.toString(uint256(IStrategyVaultV2(vaults[i]).depth())),
                "}"
            );
        }
        result = string.concat(result, "]");
    }

    function _aigr() internal view returns (Spec memory) {
        return Spec({
            name: "AI Growth",
            symbol: "AIGR",
            description: "Tilt toward AI compute and analytics: Palantir, AMD and Amazon, rebalanced weekly.",
            tagA: "ai",
            tagB: "growth",
            maxWeightBps: 4000,
            interval: 7 days,
            seedWhole: 5000,
            constituents: _three(_s(PLTR, 3500), _s(AMD, 3500), _s(AMZN, 3000))
        });
    }

    function _strm() internal view returns (Spec memory) {
        return Spec({
            name: "Streaming Giants",
            symbol: "STRM",
            description: "Streaming and cloud scale: Netflix and Amazon, rebalanced every three days.",
            tagA: "media",
            tagB: "streaming",
            maxWeightBps: 6000,
            interval: 3 days,
            seedWhole: 2500,
            constituents: _two(_s(NFLX, 6000), _s(AMZN, 4000))
        });
    }

    function _evmo() internal view returns (Spec memory) {
        return Spec({
            name: "EV Momentum",
            symbol: "EVMO",
            description: "Momentum on electric vehicles and chips: Tesla, AMD and Palantir, rebalanced daily.",
            tagA: "momentum",
            tagB: "ev",
            maxWeightBps: 4000,
            interval: 1 days,
            seedWhole: 3000,
            constituents: _three(_s(TSLA, 4000), _s(AMD, 3000), _s(PLTR, 3000))
        });
    }

    function _eq5() internal view returns (Spec memory) {
        return Spec({
            name: "Big Five Equal",
            symbol: "EQ5",
            description: "Equal weight across Tesla, Amazon, Netflix, Palantir and AMD, rebalanced weekly.",
            tagA: "equal-weight",
            tagB: "index",
            maxWeightBps: 2000,
            interval: 7 days,
            seedWhole: 4000,
            constituents: _five(_s(TSLA, 2000), _s(AMZN, 2000), _s(NFLX, 2000), _s(PLTR, 2000), _s(AMD, 2000))
        });
    }

    function _defc() internal view returns (Spec memory) {
        return Spec({
            name: "Defensive Core",
            symbol: "DEFC",
            description: "A steadier core: Amazon, Netflix and AMD, rebalanced weekly.",
            tagA: "core",
            tagB: "defensive",
            maxWeightBps: 4000,
            interval: 7 days,
            seedWhole: 1500,
            constituents: _three(_s(AMZN, 4000), _s(NFLX, 3000), _s(AMD, 3000))
        });
    }

    function _chip() internal view returns (Spec memory) {
        return Spec({
            name: "Chip Tilt",
            symbol: "CHIP",
            description: "A semiconductor tilt: AMD with a Tesla satellite, rebalanced every two weeks.",
            tagA: "semis",
            tagB: "tilt",
            maxWeightBps: 6000,
            interval: 14 days,
            seedWhole: 1000,
            constituents: _two(_s(AMD, 6000), _s(TSLA, 4000))
        });
    }

    function _bltz() internal view returns (Spec memory) {
        return Spec({
            name: "High Beta Blitz",
            symbol: "BLTZ",
            description: "A high beta pair, Palantir and Tesla, rebalanced every hour.",
            tagA: "high-beta",
            tagB: "fast",
            maxWeightBps: 5000,
            interval: 1 hours,
            seedWhole: 2000,
            constituents: _two(_s(PLTR, 5000), _s(TSLA, 5000))
        });
    }

    function _clcm() internal view returns (Spec memory) {
        return Spec({
            name: "Cloud & Commerce",
            symbol: "CLCM",
            description: "Cloud and commerce: Amazon, Palantir and Netflix, rebalanced weekly.",
            tagA: "cloud",
            tagB: "commerce",
            maxWeightBps: 5000,
            interval: 7 days,
            seedWhole: 2500,
            constituents: _three(_s(AMZN, 5000), _s(PLTR, 2500), _s(NFLX, 2500))
        });
    }

    function _core() internal view returns (Spec memory) {
        return Spec({
            name: "Core Satellite",
            symbol: "CORE",
            description: "Composed strategy: AI Growth and Big Five Equal plus a Tesla satellite.",
            tagA: "composed",
            tagB: "core",
            maxWeightBps: 4000,
            interval: 7 days,
            seedWhole: 3500,
            constituents: _three(_t(0, 4000), _t(3, 4000), _s(TSLA, 2000))
        });
    }

    function _conv() internal view returns (Spec memory) {
        return Spec({
            name: "Conviction Mix",
            symbol: "CONV",
            description: "Composed strategy: Streaming Giants and Chip Tilt plus a Palantir satellite.",
            tagA: "composed",
            tagB: "conviction",
            maxWeightBps: 4000,
            interval: 1 days,
            seedWhole: 1200,
            constituents: _three(_t(1, 4000), _t(5, 3000), _s(PLTR, 3000))
        });
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
