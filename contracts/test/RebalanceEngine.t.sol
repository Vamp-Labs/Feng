// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelper} from "./helpers/DeployHelper.sol";
import {StrategyVault} from "../StrategyVault.sol";
import {RebalanceEngine} from "../RebalanceEngine.sol";
import {Constituent} from "../interfaces/IStrategyVault.sol";

contract RebalanceEngineTest is DeployHelper {
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    StrategyVault internal vault;

    function setUp() public {
        _deployCore();
        Constituent[] memory c = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (address v,) = factory.createStrategy("Solo", "SOLO", c, 10_000, 7 days);
        vault = StrategyVault(v);

        _mintUsdg(alice, 1000e18);
        vm.startPrank(alice);
        usdg.approve(address(vault), 1000e18);
        vault.deposit(1000e18, alice);
        vm.stopPrank();
    }

    function test_performRebalance_revertsWhenNotNeeded() public {
        vm.expectRevert(abi.encodeWithSelector(RebalanceEngine.RebalanceNotNeeded.selector, address(vault)));
        engine.performRebalance(address(vault));
    }

    function test_performRebalance_succeedsWhenNeeded() public {
        vm.warp(block.timestamp + 7 days + 1);
        _refreshFeeds();
        engine.performRebalance(address(vault));
        assertEq(vault.lastRebalanceTimestamp(), block.timestamp);
    }

    function test_checkUpkeep_listsVaultsNeedingRebalance() public {
        address[] memory before = engine.checkUpkeep();
        assertEq(before.length, 0);

        vm.warp(block.timestamp + 7 days + 1);
        address[] memory after_ = engine.checkUpkeep();
        assertEq(after_.length, 1);
        assertEq(after_[0], address(vault));
    }

    function test_performRebalance_isPermissionless() public {
        vm.warp(block.timestamp + 7 days + 1);
        _refreshFeeds();
        vm.prank(makeAddr("randomKeeper"));
        engine.performRebalance(address(vault));
    }
}
