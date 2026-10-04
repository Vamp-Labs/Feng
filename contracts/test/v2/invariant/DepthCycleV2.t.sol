// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";

contract DepthCycleV2Test is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function _single(address token, bool strat) internal pure returns (Constituent[] memory c) {
        c = new Constituent[](1);
        c[0] = Constituent({token: token, targetWeightBps: 10_000, isStrategyToken: strat});
    }

    function test_chainOfNestedStrategies_neverExceedsMaxDepth(uint8 depth) public {
        depth = uint8(bound(depth, 1, 6));
        address cur = address(stocks[0]);
        bool curStrat;
        uint8 curDepth;
        for (uint8 i = 1; i <= depth; i++) {
            if (curDepth + 1 > factory.MAX_DEPTH()) {
                vm.prank(creator);
                vm.expectRevert();
                factory.createStrategy("Chain", "CHAIN", _single(cur, curStrat), 10_000, 7 days, 100, _meta());
                return;
            }
            vm.prank(creator);
            (address vv, address tt) =
                factory.createStrategy("Chain", "CHAIN", _single(cur, curStrat), 10_000, 7 days, 100, _meta());
            assertEq(IStrategyVaultV2(vv).depth(), curDepth + 1);
            cur = tt;
            curStrat = true;
            curDepth = IStrategyVaultV2(vv).depth();
        }
    }

    function test_unknownStrategyTokenConstituent_alwaysReverts(address foreign) public {
        vm.assume(foreign != address(0));
        vm.assume(factory.vaultOf(foreign) == address(0));
        vm.prank(creator);
        vm.expectPartialRevert(_sel("UnknownStrategyToken()"));
        factory.createStrategy("F", "FG", _single(foreign, true), 10_000, 7 days, 100, _meta());
    }

    function test_duplicateReverts() public {
        Constituent[] memory c = _two(address(stocks[0]), 5000, address(stocks[0]), 5000);
        vm.prank(creator);
        vm.expectPartialRevert(_sel("DuplicateConstituent()"));
        factory.createStrategy("D", "DD", c, 5000, 7 days, 100, _meta());
    }

    function test_strategyCannotContainItselfOrAncestor() public {
        (, address t1) = _fiftyFifty();
        vm.prank(creator);
        (, address t2) = factory.createStrategy("D2", "D2", _single(t1, true), 10_000, 7 days, 100, _meta());
        Constituent[] memory c = _two(t1, 5000, t2, 5000);
        c[0].isStrategyToken = true;
        c[1].isStrategyToken = true;
        vm.prank(creator);
        vm.expectRevert();
        factory.createStrategy("D3", "D3", c, 5000, 7 days, 100, _meta());
    }
}
