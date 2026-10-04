// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelper} from "../helpers/DeployHelper.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {StrategyVault} from "../../StrategyVault.sol";
import {StrategyToken} from "../../StrategyToken.sol";
import {Constituent} from "../../interfaces/IStrategyVault.sol";

/// @notice Fuzzes StrategyFactory's MAX_DEPTH=2 enforcement and ancestor/leaf-graph validation
/// across randomized chains of nesting, asserting the factory never allows a depth-3+
/// composition to be created, regardless of how the chain is built.
contract DepthCycleTest is DeployHelper {
    address internal creator = makeAddr("creator");

    function setUp() public {
        _deployCore();
    }

    /// @dev Builds a chain of `depth` strategies, each depth-N nesting the previous depth-(N-1)
    /// token 100%, and asserts: every creation up to and including MAX_DEPTH succeeds with the
    /// expected depth, and the first attempt to exceed MAX_DEPTH always reverts.
    function test_chainOfNestedStrategies_neverExceedsMaxDepth(uint8 depth) public {
        depth = uint8(bound(depth, 1, 6));

        address currentToken = address(tsla);
        bool currentIsStrategyToken = false;
        uint8 currentDepth = 0;

        for (uint8 i = 1; i <= depth; i++) {
            Constituent[] memory c = new Constituent[](1);
            c[0] = Constituent({token: currentToken, targetWeightBps: 10_000, isStrategyToken: currentIsStrategyToken});

            vm.prank(creator);
            if (currentDepth + 1 > factory.MAX_DEPTH()) {
                vm.expectRevert();
                factory.createStrategy("Chain", "CHAIN", c, 10_000, 7 days);
                return;
            }

            (address vault, address token) = factory.createStrategy("Chain", "CHAIN", c, 10_000, 7 days);
            assertEq(StrategyVault(vault).depth(), currentDepth + 1);

            currentToken = token;
            currentIsStrategyToken = true;
            currentDepth = StrategyVault(vault).depth();
        }
    }

    function test_depth3_alwaysReverts() public {
        Constituent[] memory c1 = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (, address d1) = factory.createStrategy("D1", "D1", c1, 10_000, 7 days);

        Constituent[] memory c2 = new Constituent[](1);
        c2[0] = Constituent({token: d1, targetWeightBps: 10_000, isStrategyToken: true});
        vm.prank(creator);
        (, address d2) = factory.createStrategy("D2", "D2", c2, 10_000, 7 days);

        Constituent[] memory c3 = new Constituent[](1);
        c3[0] = Constituent({token: d2, targetWeightBps: 10_000, isStrategyToken: true});

        vm.prank(creator);
        vm.expectRevert(StrategyFactory.DepthExceeded.selector);
        factory.createStrategy("D3", "D3", c3, 10_000, 7 days);
    }

    /// @dev A strategy can never list a StrategyToken constituent that the factory did not
    /// itself create (i.e. an arbitrary/foreign address masquerading as a StrategyToken),
    /// which is the on-chain guard against constructing an out-of-band cycle.
    function test_unknownStrategyTokenConstituent_alwaysReverts(address foreignToken) public {
        vm.assume(foreignToken != address(0));
        vm.assume(factory.vaultOf(foreignToken) == address(0));

        Constituent[] memory c = new Constituent[](1);
        c[0] = Constituent({token: foreignToken, targetWeightBps: 10_000, isStrategyToken: true});

        vm.prank(creator);
        vm.expectRevert(StrategyFactory.UnknownStrategyToken.selector);
        factory.createStrategy("Foreign", "FGN", c, 10_000, 7 days);
    }

    /// @dev A strategy token can never appear twice in the same constituent list, which would
    /// otherwise let a single creation call double-count (and thus misprice) one constituent.
    function test_duplicateConstituent_alwaysReverts(uint16 w1, uint16 w2) public {
        w1 = uint16(bound(w1, 1, 9_999));
        w2 = uint16(10_000 - w1);

        Constituent[] memory c = new Constituent[](2);
        c[0] = Constituent({token: address(tsla), targetWeightBps: w1, isStrategyToken: false});
        c[1] = Constituent({token: address(tsla), targetWeightBps: w2, isStrategyToken: false});

        vm.prank(creator);
        vm.expectRevert(StrategyFactory.DuplicateConstituent.selector);
        factory.createStrategy("Dup", "DUP", c, 10_000, 7 days);
    }
}
