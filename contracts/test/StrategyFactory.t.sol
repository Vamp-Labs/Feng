// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelper} from "./helpers/DeployHelper.sol";
import {StrategyFactory} from "../StrategyFactory.sol";
import {StrategyVault} from "../StrategyVault.sol";
import {Constituent} from "../interfaces/IStrategyVault.sol";

contract StrategyFactoryTest is DeployHelper {
    address internal creator = makeAddr("creator");

    function setUp() public {
        _deployCore();
    }

    function test_createStrategy_depth1_succeeds() public {
        Constituent[] memory c = _twoAssetConstituents(address(tsla), 6000, address(amzn), 4000);

        vm.prank(creator);
        (address vault, address token) = factory.createStrategy("Tech Basket", "TECH", c, 6000, 7 days);

        assertEq(StrategyVault(vault).depth(), 1);
        assertTrue(token != address(0));
        assertEq(factory.vaultOf(token), vault);
    }

    function test_createStrategy_depth2_succeeds() public {
        Constituent[] memory c1 = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (address depth1Vault, address depth1Token) = factory.createStrategy("Solo TSLA", "STSLA", c1, 10_000, 7 days);

        Constituent[] memory c2 = new Constituent[](1);
        c2[0] = Constituent({token: depth1Token, targetWeightBps: 10_000, isStrategyToken: true});

        vm.prank(creator);
        (address depth2Vault,) = factory.createStrategy("Wrapped Solo", "WSOLO", c2, 10_000, 7 days);

        assertEq(StrategyVault(depth2Vault).depth(), 2);
        assertEq(depth1Vault, factory.vaultOf(depth1Token));
    }

    function test_createStrategy_depth3_reverts() public {
        Constituent[] memory c1 = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (, address depth1Token) = factory.createStrategy("D1", "D1", c1, 10_000, 7 days);

        Constituent[] memory c2 = new Constituent[](1);
        c2[0] = Constituent({token: depth1Token, targetWeightBps: 10_000, isStrategyToken: true});
        vm.prank(creator);
        (, address depth2Token) = factory.createStrategy("D2", "D2", c2, 10_000, 7 days);

        Constituent[] memory c3 = new Constituent[](1);
        c3[0] = Constituent({token: depth2Token, targetWeightBps: 10_000, isStrategyToken: true});

        vm.prank(creator);
        vm.expectRevert(StrategyFactory.DepthExceeded.selector);
        factory.createStrategy("D3", "D3", c3, 10_000, 7 days);
    }

    function test_createStrategy_revertsOnBadWeightSum() public {
        Constituent[] memory c = _twoAssetConstituents(address(tsla), 6000, address(amzn), 3000);
        vm.prank(creator);
        vm.expectRevert(StrategyFactory.WeightsMustSumTo10000.selector);
        factory.createStrategy("Bad", "BAD", c, 10_000, 7 days);
    }

    function test_createStrategy_revertsOnDuplicateConstituent() public {
        Constituent[] memory c = _twoAssetConstituents(address(tsla), 5000, address(tsla), 5000);
        vm.prank(creator);
        vm.expectRevert(StrategyFactory.DuplicateConstituent.selector);
        factory.createStrategy("Dup", "DUP", c, 10_000, 7 days);
    }

    function test_createStrategy_revertsOnUnknownStrategyToken() public {
        Constituent[] memory c = new Constituent[](1);
        c[0] = Constituent({token: makeAddr("fakeToken"), targetWeightBps: 10_000, isStrategyToken: true});
        vm.prank(creator);
        vm.expectRevert(StrategyFactory.UnknownStrategyToken.selector);
        factory.createStrategy("Fake", "FAKE", c, 10_000, 7 days);
    }

    function test_createStrategy_revertsOnMaxWeightExceededPerAsset() public {
        Constituent[] memory c = _twoAssetConstituents(address(tsla), 8000, address(amzn), 2000);
        vm.prank(creator);
        vm.expectRevert(StrategyFactory.MaxWeightExceeded.selector);
        factory.createStrategy("TooConcentrated", "TC", c, 5000, 7 days);
    }

    function test_createStrategy_grantsMinterRoleToNewVault() public {
        Constituent[] memory c = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (address vault,) = factory.createStrategy("Solo", "SOLO", c, 10_000, 7 days);
        assertTrue(tsla.hasRole(tsla.MINTER_ROLE(), vault));
    }
}
