// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2, VaultParams} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IMarketplaceRegistryV2, StrategyMeta, StrategyInfoV2} from "../../../v2/interfaces/IMarketplaceRegistryV2.sol";

contract RegistryV2Test is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function _mk(string memory desc, string[] memory tags) internal pure returns (StrategyMeta memory m) {
        m.description = desc;
        m.tags = tags;
    }

    function _tags(string memory a) internal pure returns (string[] memory t) {
        t = new string[](1);
        t[0] = a;
    }

    function _bytesOf(uint256 n) internal pure returns (string memory) {
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            b[i] = "a";
        }
        return string(b);
    }

    function _create(StrategyMeta memory m) internal returns (address v, address t) {
        vm.prank(creator);
        (v, t) = factory.createStrategy(
            "N", "NN", _two(address(stocks[0]), 5000, address(stocks[1]), 5000), 5000, 7 days, 100, m
        );
    }

    function test_metaLimits() public {
        _create(_mk(_bytesOf(160), _tags(_bytesOf(16))));
        vm.expectPartialRevert(_sel("DescriptionTooLong()"));
        _create(_mk(_bytesOf(161), _tags("a")));
        string[] memory four = new string[](4);
        four[0] = "a";
        four[1] = "b";
        four[2] = "c";
        four[3] = "d";
        vm.expectPartialRevert(_sel("TooManyTags()"));
        _create(_mk("x", four));
        vm.expectPartialRevert(_sel("InvalidTag()"));
        _create(_mk("x", _tags("Upper")));
        vm.expectPartialRevert(_sel("InvalidTag()"));
        _create(_mk("x", _tags("")));
        vm.expectPartialRevert(_sel("InvalidTag()"));
        _create(_mk("x", _tags(_bytesOf(17))));
        vm.expectPartialRevert(_sel("InvalidTag()"));
        _create(_mk("x", _tags("a b")));
        string[] memory dup = new string[](2);
        dup[0] = "ai";
        dup[1] = "ai";
        vm.expectPartialRevert(_sel("DuplicateTag()"));
        _create(_mk("x", dup));
        string[] memory ok = new string[](3);
        ok[0] = "a-1";
        ok[1] = "b2";
        ok[2] = "0-9";
        _create(_mk("x", ok));
        _create(_mk("", new string[](0)));
    }

    function test_updateMeta_onlyCreator() public {
        (address v,) = _create(_mk("one", _tags("a")));
        vm.prank(attacker);
        vm.expectPartialRevert(_sel("NotCreator()"));
        registry.updateMeta(v, _mk("hack", _tags("a")));
        vm.prank(creator);
        registry.updateMeta(v, _mk("two", _tags("b")));
        StrategyMeta memory m = registry.getStrategyMeta(v);
        assertEq(m.description, "two");
        assertEq(m.tags[0], "b");
        vm.prank(creator);
        vm.expectPartialRevert(_sel("InvalidTag()"));
        registry.updateMeta(v, _mk("two", _tags("B")));
        vm.prank(creator);
        vm.expectPartialRevert(_sel("NotRegistered()"));
        registry.updateMeta(address(0x1234), _mk("two", _tags("b")));
    }

    function test_updateMeta_emits() public {
        (address v,) = _create(_mk("one", _tags("a")));
        vm.recordLogs();
        vm.prank(creator);
        registry.updateMeta(v, _mk("two", _tags("b")));
        Vm.Log[] memory l = vm.getRecordedLogs();
        assertEq(l.length, 1);
        assertEq(l[0].topics[0], keccak256("MetaUpdated(address,string,string[])"));
    }

    function test_registerOnlyFactoryRole() public {
        (address v, address t) = _create(_mk("one", _tags("a")));
        vm.prank(attacker);
        vm.expectRevert();
        registry.registerStrategy(v, t, attacker, _mk("x", _tags("a")));
        vm.startPrank(admin);
        registry.grantRole(registry.FACTORY_ROLE(), admin);
        vm.expectPartialRevert(_sel("AlreadyRegistered()"));
        registry.registerStrategy(v, t, admin, _mk("x", _tags("a")));
        vm.stopPrank();
    }

    function test_pagination() public {
        address[] memory vs = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            (vs[i],) = _create(_mk("x", _tags("a")));
        }
        assertEq(registry.strategyCount(), 5);
        assertEq(registry.getAllStrategies().length, 5);
        address[] memory p = registry.getStrategies(1, 2);
        assertEq(p.length, 2);
        assertEq(p[0], vs[1]);
        assertEq(p[1], vs[2]);
        p = registry.getStrategies(3, 100);
        assertEq(p.length, 2);
        assertEq(p[1], vs[4]);
        assertEq(registry.getStrategies(5, 1).length, 0);
        assertEq(registry.getStrategies(99, 1).length, 0);
        assertEq(registry.getStrategies(0, 0).length, 0);
        assertEq(registry.getStrategies(0, type(uint256).max).length, 5);
    }

    function test_infoViews() public {
        (address v, address t) = _create(_mk("desc", _tags("tag")));
        assertFalse(registry.isRegistered(address(0xBAD)));
        assertTrue(registry.isRegistered(v));
        StrategyInfoV2 memory i = registry.getStrategyInfoV2(v);
        assertEq(i.vault, v);
        assertEq(i.token, t);
        assertEq(i.creator, creator);
        assertEq(i.depth, 1);
        assertEq(i.createdAt, block.timestamp);
        assertEq(i.description, "desc");
        assertEq(i.tags[0], "tag");
    }
}

contract EngineV2Test is DeployV2Helper {
    IStrategyVaultV2 internal a;
    IStrategyVaultV2 internal b;

    function setUp() public {
        _deployStack();
        (a,) = _create("AAA", _two(address(stocks[0]), 5000, address(stocks[1]), 5000), 5000, 1 days);
        (b,) = _create("BBB", _two(address(stocks[2]), 5000, address(stocks[1]), 5000), 5000, 1 days);
    }

    function test_checkUpkeep_listsDueVaults() public {
        _deposit(a, alice, 1000 * U);
        _deposit(b, alice, 1000 * U);
        assertEq(engine.checkUpkeep().length, 0);
        _skewAndAge(1 days);
        address[] memory due = engine.checkUpkeep();
        assertEq(due.length, 2);
        assertEq(engine.MAX_SCAN(), 200);
        assertEq(engine.registry(), address(registry));
    }

    function test_checkUpkeep_skipsFailingVault() public {
        _deposit(a, alice, 1000 * U);
        _deposit(b, alice, 1000 * U);
        _skewAndAge(1 days);
        vm.prank(admin);
        oracle.removeFeed(address(stocks[0]));
        address[] memory due = engine.checkUpkeep();
        assertEq(due.length, 1);
        assertEq(due[0], address(b));
    }

    function test_checkUpkeepRange_pages() public {
        _deposit(a, alice, 1000 * U);
        _deposit(b, alice, 1000 * U);
        _skewAndAge(1 days);
        address[] memory p0 = engine.checkUpkeepRange(0, 1);
        address[] memory p1 = engine.checkUpkeepRange(1, 1);
        assertEq(p0.length, 1);
        assertEq(p1.length, 1);
        assertEq(p0[0], address(a));
        assertEq(p1[0], address(b));
        assertEq(engine.checkUpkeepRange(5, 3).length, 0);
        assertEq(engine.checkUpkeepRange(0, 10).length, 2);
    }

    function test_performRebalance_registryGate() public {
        VaultParams memory p;
        p.name = "S";
        p.symbol = "SS";
        p.usdg = usdg;
        p.oracle = address(oracle);
        p.venue = address(desk);
        p.guardian = attacker;
        p.constituents = _two(address(stocks[0]), 5000, address(stocks[1]), 5000);
        p.maxWeightBps = 5000;
        p.maxSlippageBps = 100;
        p.depth = 1;
        p.rebalanceInterval = 1 days;
        p.maxPriceStaleness = STALENESS;
        vm.prank(attacker);
        (address v,) = deployer.deploy(p);
        vm.expectPartialRevert(_sel("NotRegisteredVault(address)"));
        engine.performRebalance(v);
    }

    function test_performRebalance_notNeededAndHappyPath() public {
        _deposit(a, alice, 1000 * U);
        vm.expectPartialRevert(_sel("RebalanceNotNeeded(address)"));
        engine.performRebalance(address(a));
        _skewAndAge(1 days);
        vm.recordLogs();
        vm.prank(keeper);
        engine.performRebalance(address(a));
        Vm.Log[] memory l = vm.getRecordedLogs();
        assertGe(_indexOf(l, address(engine), keccak256("RebalancePerformed(address,address)")), 0);
        assertEq(a.lastRebalanceTimestamp(), block.timestamp);
    }

    function test_checkpoint_skipsUnregisteredAndReverting() public {
        _deposit(a, alice, 1000 * U);
        _deposit(b, alice, 1000 * U);
        vm.warp(block.timestamp + 31 minutes);
        _refreshAll();
        _deposit(b, bob, 10 * U);
        address[] memory list = new address[](3);
        list[0] = address(a);
        list[1] = address(0xBAD);
        list[2] = address(b);
        vm.recordLogs();
        uint256 n = engine.checkpoint(list);
        assertEq(n, 1);
        assertGe(
            _indexOf(vm.getRecordedLogs(), address(engine), keccak256("CheckpointsRecorded(address,uint256,uint256)")),
            0
        );
        assertEq(engine.checkpoint(new address[](0)), 0);
    }
}
