// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelper} from "./helpers/DeployHelper.sol";
import {MarketplaceRegistry} from "../MarketplaceRegistry.sol";
import {Constituent} from "../interfaces/IStrategyVault.sol";

contract MarketplaceRegistryTest is DeployHelper {
    address internal creator = makeAddr("creator");

    function setUp() public {
        _deployCore();
    }

    function test_registerStrategy_onlyFactory() public {
        vm.prank(makeAddr("notFactory"));
        vm.expectRevert();
        registry.registerStrategy(makeAddr("vault"), makeAddr("token"), creator);
    }

    function test_createStrategy_autoRegisters() public {
        Constituent[] memory c = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (address vault, address token) = factory.createStrategy("Solo", "SOLO", c, 10_000, 7 days);

        address[] memory all = registry.getAllStrategies();
        assertEq(all.length, 1);
        assertEq(all[0], vault);

        (address regToken, address regCreator, uint8 regDepth,) = registry.getStrategyInfo(vault);
        assertEq(regToken, token);
        assertEq(regCreator, creator);
        assertEq(regDepth, 1);
    }

    function test_getStrategyInfo_revertsForUnregisteredVault() public {
        vm.expectRevert(MarketplaceRegistry.NotRegistered.selector);
        registry.getStrategyInfo(makeAddr("unknown"));
    }

    function test_registerStrategy_revertsOnDuplicate() public {
        Constituent[] memory c = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (address vault, address token) = factory.createStrategy("Solo", "SOLO", c, 10_000, 7 days);

        vm.prank(address(factory));
        vm.expectRevert(MarketplaceRegistry.AlreadyRegistered.selector);
        registry.registerStrategy(vault, token, creator);
    }
}
