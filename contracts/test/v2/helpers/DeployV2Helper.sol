// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IPriceOracleV2} from "../../../v2/interfaces/IPriceOracleV2.sol";
import {IVenue} from "../../../v2/interfaces/IVenue.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IMarketplaceRegistryV2, StrategyMeta} from "../../../v2/interfaces/IMarketplaceRegistryV2.sol";
import {IStrategyFactoryV2} from "../../../v2/interfaces/IStrategyFactoryV2.sol";
import {IRebalanceEngineV2} from "../../../v2/interfaces/IRebalanceEngineV2.sol";
import {IOracleDesk} from "../../../v2/interfaces/IOracleDesk.sol";
import {IFengAggregator} from "../../../v2/interfaces/IFengAggregator.sol";
import {MockUSDGV2} from "../../../v2/mocks/MockUSDGV2.sol";
import {FengAggregator} from "../../../v2/oracle/FengAggregator.sol";
import {ChainlinkPriceOracleV2} from "../../../v2/oracle/ChainlinkPriceOracleV2.sol";
import {MarketplaceRegistryV2} from "../../../v2/MarketplaceRegistryV2.sol";
import {OracleDesk} from "../../../v2/venue/OracleDesk.sol";
import {VaultDeployerV2} from "../../../v2/VaultDeployerV2.sol";
import {StrategyFactoryV2} from "../../../v2/StrategyFactoryV2.sol";
import {StrategyLens} from "../../../v2/StrategyLens.sol";
import {RebalanceEngineV2} from "../../../v2/RebalanceEngineV2.sol";
import {TestToken} from "../mocks/HostileTokens.sol";

interface IMintLike {
    function mint(address to, uint256 amount) external;
}

abstract contract DeployV2Helper is Test {
    uint256 internal constant T0 = 1_700_000_000;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant STALENESS = 12 hours;
    uint16 internal constant SPREAD = 10;

    address internal admin = makeAddr("admin");
    address internal guardian = makeAddr("guardian");
    address internal relayer = makeAddr("relayer");
    address internal keeper = makeAddr("keeper");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal attacker = makeAddr("attacker");

    address internal usdg;
    uint256 internal U;
    uint8 internal usdgDec;

    ChainlinkPriceOracleV2 internal oracle;
    MarketplaceRegistryV2 internal registry;
    OracleDesk internal desk;
    VaultDeployerV2 internal deployer;
    StrategyFactoryV2 internal factory;
    RebalanceEngineV2 internal engine;
    StrategyLens internal lens;

    TestToken[] internal stocks;
    FengAggregator[] internal feeds;

    uint8 internal cfgUsdg = 6;
    uint8 internal cfgStock = 18;

    function _usdgDecimals() internal view virtual returns (uint8) {
        return cfgUsdg;
    }

    function _stockDecimals() internal view virtual returns (uint8) {
        return cfgStock;
    }

    function _makeUsdg() internal virtual returns (address) {
        return address(new MockUSDGV2(admin, _usdgDecimals()));
    }

    function _deployStack() internal {
        vm.warp(T0);
        usdgDec = _usdgDecimals();
        U = 10 ** usdgDec;
        vm.startPrank(admin);
        usdg = _makeUsdg();
        oracle = new ChainlinkPriceOracleV2(admin);
        registry = new MarketplaceRegistryV2(admin);
        desk = new OracleDesk(admin, usdg, address(oracle), address(registry), SPREAD, STALENESS);
        deployer = new VaultDeployerV2();
        factory = new StrategyFactoryV2(
            address(registry), address(oracle), address(desk), usdg, guardian, address(deployer), STALENESS
        );
        engine = new RebalanceEngineV2(address(registry));
        lens = new StrategyLens();
        registry.grantRole(registry.FACTORY_ROLE(), address(factory));
        IMintLike(usdg).mint(admin, 10_000_000 * U);
        IERC20(usdg).approve(address(desk), type(uint256).max);
        desk.fundReserve(10_000_000 * U);
        vm.stopPrank();
        _newStock("TSLA", _stockDecimals(), 400e8);
        _newStock("AMZN", _stockDecimals(), 250e8);
        _newStock("NFLX", _stockDecimals(), 100e8);
    }

    function _newStock(string memory sym, uint8 dec, int256 price8) internal returns (TestToken t) {
        vm.startPrank(admin);
        t = new TestToken(sym, sym, dec);
        FengAggregator f = new FengAggregator(admin, 8, sym, price8, 1500, 3000);
        f.grantRole(f.UPDATER_ROLE(), relayer);
        f.grantRole(f.SHOCK_ROLE(), relayer);
        f.setShockEnabled(true);
        oracle.setFeed(address(t), address(f));
        desk.setToken(address(t), IOracleDesk.Mode.Mint);
        t.grantRole(t.MINTER_ROLE(), address(desk));
        vm.stopPrank();
        stocks.push(t);
        feeds.push(f);
    }

    function _newInventoryToken(address token, int256 price8, uint256 inventory) internal returns (FengAggregator f) {
        vm.startPrank(admin);
        f = new FengAggregator(admin, 8, "INV", price8, 1500, 3000);
        f.grantRole(f.UPDATER_ROLE(), relayer);
        oracle.setFeed(token, address(f));
        desk.setToken(token, IOracleDesk.Mode.Inventory);
        IMintLike(token).mint(admin, inventory);
        (bool okA,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, address(desk), inventory));
        require(okA);
        desk.fundInventory(token, inventory);
        vm.stopPrank();
        stocks.push(TestToken(token));
        feeds.push(f);
    }

    function _meta() internal pure returns (StrategyMeta memory m) {
        m.description = "Test strategy";
        m.tags = new string[](1);
        m.tags[0] = "test";
    }

    function _cons(address[] memory toks, uint16[] memory w) internal pure returns (Constituent[] memory c) {
        c = new Constituent[](toks.length);
        for (uint256 i = 0; i < toks.length; i++) {
            c[i] = Constituent({token: toks[i], targetWeightBps: w[i], isStrategyToken: false});
        }
    }

    function _two(address a, uint16 wa, address b, uint16 wb) internal pure returns (Constituent[] memory c) {
        c = new Constituent[](2);
        c[0] = Constituent({token: a, targetWeightBps: wa, isStrategyToken: false});
        c[1] = Constituent({token: b, targetWeightBps: wb, isStrategyToken: false});
    }

    function _createWith(
        IStrategyFactoryV2 f,
        string memory sym,
        Constituent[] memory c,
        uint16 maxW,
        uint256 interval,
        uint16 slip
    ) internal returns (IStrategyVaultV2 v, address token) {
        vm.prank(creator);
        (address va, address t) = f.createStrategy(sym, sym, c, maxW, interval, slip, _meta());
        v = IStrategyVaultV2(va);
        token = t;
    }

    function _create(string memory sym, Constituent[] memory c, uint16 maxW, uint256 interval)
        internal
        returns (IStrategyVaultV2 v, address token)
    {
        return _createWith(IStrategyFactoryV2(address(factory)), sym, c, maxW, interval, 100);
    }

    function _fiftyFifty() internal returns (IStrategyVaultV2 v, address token) {
        return _create("FIFTY", _two(address(stocks[0]), 5000, address(stocks[1]), 5000), 5000, 7 days);
    }

    function _threeAsset() internal returns (IStrategyVaultV2 v, address token) {
        address[] memory t = new address[](3);
        uint16[] memory w = new uint16[](3);
        t[0] = address(stocks[0]);
        t[1] = address(stocks[1]);
        t[2] = address(stocks[2]);
        w[0] = 4000;
        w[1] = 3500;
        w[2] = 2500;
        return _create("THREE", _cons(t, w), 4500, 3 days);
    }

    function _nested(IStrategyVaultV2 childVault, address childToken)
        internal
        returns (IStrategyVaultV2 p, address pt)
    {
        Constituent[] memory c = new Constituent[](2);
        c[0] = Constituent({token: childToken, targetWeightBps: 6000, isStrategyToken: true});
        c[1] = Constituent({token: address(stocks[2]), targetWeightBps: 4000, isStrategyToken: false});
        childVault;
        return _create("PARENT", c, 6000, 7 days);
    }

    function _mintUsdg(address to, uint256 amt) internal {
        vm.prank(admin);
        IMintLike(usdg).mint(to, amt);
    }

    function _deposit(IStrategyVaultV2 v, address who, uint256 amt) internal returns (uint256 shares) {
        _mintUsdg(who, amt);
        vm.startPrank(who);
        IERC20(usdg).approve(address(v), amt);
        shares = v.deposit(amt, who, 0);
        vm.stopPrank();
    }

    function _setPrice(uint256 idx, int256 price8) internal {
        vm.prank(relayer);
        feeds[idx].updateAnswer(price8);
    }

    function _refreshAll() internal {
        vm.startPrank(relayer);
        for (uint256 i = 0; i < feeds.length; i++) {
            feeds[i].refresh();
        }
        vm.stopPrank();
    }

    function _price18(address token) internal view returns (uint256 p) {
        (p,) = oracle.getPrice(token);
    }

    function _valueOf(address token, uint256 amount, bool ceil) internal view returns (uint256) {
        uint8 dec = IERC20Metadata(token).decimals();
        uint256 den = 10 ** (uint256(dec) + 18 - usdgDec);
        uint256 num = amount * _price18(token);
        uint256 q = num / den;
        if (ceil && num % den != 0) q += 1;
        return q;
    }

    function _navIndep(IStrategyVaultV2 v, bool ceil) internal view returns (uint256 nav) {
        nav = IERC20(usdg).balanceOf(address(v));
        Constituent[] memory cs = v.getConstituents();
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 bal = IERC20(cs[i].token).balanceOf(address(v));
            if (cs[i].isStrategyToken) {
                address childVault = factory.vaultOf(cs[i].token);
                nav += IStrategyVaultV2(childVault).previewRedeem(bal) + (ceil && bal > 0 ? 1 : 0);
            } else {
                nav += _valueOf(cs[i].token, bal, ceil);
            }
        }
    }

    function _shareToken(IStrategyVaultV2 v) internal view returns (IERC20) {
        return IERC20(v.token());
    }

    function _sel(string memory sig) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(sig)));
    }

    function _hasRole(address c, bytes32 role, address who) internal view returns (bool) {
        return IAccessControl(c).hasRole(role, who);
    }

    bytes32 internal constant LEG_TOPIC = keccak256("LegTraded(address,bool,uint256,uint256)");
    bytes32 internal constant NAV_TOPIC = keccak256("NavCheckpoint(uint256,uint256,uint256)");
    bytes32 internal constant REBAL_TOPIC = keccak256("Rebalanced(uint256,bool,bool,uint256)");

    function _legStats(Vm.Log[] memory logs, address vault)
        internal
        pure
        returns (uint256 sells, uint256 buys, bool sellsFirst)
    {
        sellsFirst = true;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != vault || logs[i].topics[0] != LEG_TOPIC) continue;
            (bool buy,,) = abi.decode(logs[i].data, (bool, uint256, uint256));
            if (buy) {
                buys++;
            } else {
                sells++;
                if (buys > 0) sellsFirst = false;
            }
        }
    }

    function _indexOf(Vm.Log[] memory logs, address emitter, bytes32 topic) internal pure returns (int256) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == emitter && logs[i].topics[0] == topic) return int256(i);
        }
        return -1;
    }

    function _vS() internal view returns (uint256) {
        uint256 e = 18 > uint256(usdgDec) ? 18 - uint256(usdgDec) : 0;
        return 10 ** (e > 12 ? e : 12);
    }

    function _skewAndAge(uint256 dt) internal {
        vm.warp(block.timestamp + dt);
        _refreshAll();
    }
}
