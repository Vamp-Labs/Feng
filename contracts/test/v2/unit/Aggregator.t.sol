// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FengAggregator} from "../../../v2/oracle/FengAggregator.sol";

contract AggregatorTest is Test {
    FengAggregator internal agg;
    address internal admin = makeAddr("admin");
    address internal relayer = makeAddr("relayer");
    address internal shocker = makeAddr("shocker");
    address internal rnd = makeAddr("rnd");

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event AnswerShocked(int256 indexed current, int256 indexed anchor, uint256 indexed roundId);
    event AnswerForced(int256 indexed current, uint256 indexed roundId, address indexed by);

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.startPrank(admin);
        agg = new FengAggregator(admin, 8, "TSLA / USD", 400e8, 1500, 3000);
        agg.grantRole(agg.UPDATER_ROLE(), relayer);
        agg.grantRole(agg.SHOCK_ROLE(), shocker);
        vm.stopPrank();
    }

    function _round() internal view returns (uint80 id, int256 a, uint256 upd) {
        (id, a,, upd,) = agg.latestRoundData();
    }

    function test_constructorState() public view {
        assertEq(agg.decimals(), 8);
        assertEq(agg.description(), "TSLA / USD");
        assertEq(agg.version(), 1);
        assertEq(agg.latestAnswer(), 400e8);
        assertEq(agg.anchorAnswer(), 400e8);
        assertEq(agg.maxDeviationBps(), 1500);
        assertEq(agg.maxShockBps(), 3000);
        assertFalse(agg.shockEnabled());
        assertEq(agg.MAX_DEVIATION_CAP_BPS(), 5000);
        assertEq(agg.MAX_SHOCK_CAP_BPS(), 5000);
        (, int256 a, uint256 upd) = _round();
        assertEq(a, 400e8);
        assertEq(upd, block.timestamp);
    }

    function test_updateAnswer_withinBound() public {
        vm.warp(block.timestamp + 100);
        vm.prank(relayer);
        agg.updateAnswer(460e8);
        (uint80 id, int256 a, uint256 upd) = _round();
        assertEq(a, 460e8);
        assertEq(upd, block.timestamp);
        assertEq(agg.anchorAnswer(), 400e8);
        vm.prank(relayer);
        agg.updateAnswer(391e8);
        (uint80 id2,,) = _round();
        assertGt(id2, id);
        assertEq(agg.anchorAnswer(), 400e8);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(relayer);
        agg.updateAnswer(391e8);
        assertEq(agg.anchorAnswer(), 391e8);
    }

    function _agg10() internal returns (FengAggregator a) {
        vm.startPrank(admin);
        a = new FengAggregator(admin, 8, "TSLA / USD", 400e8, 1000, 3000);
        a.grantRole(a.UPDATER_ROLE(), relayer);
        a.grantRole(a.SHOCK_ROLE(), shocker);
        a.setShockEnabled(true);
        vm.stopPrank();
    }

    function test_window_constantsAndInitialAnchor() public view {
        assertEq(agg.ANCHOR_WINDOW(), 1 hours);
        assertEq(agg.anchorSetAt(), block.timestamp);
    }

    function test_window_steppedPushesBoundedBySameAnchor() public {
        FengAggregator a = _agg10();
        uint256 t0 = block.timestamp;
        vm.startPrank(relayer);
        a.updateAnswer(404e8);
        vm.warp(t0 + 10 minutes);
        a.updateAnswer(436e8);
        vm.warp(t0 + 20 minutes);
        a.updateAnswer(439_96e6);
        assertEq(a.anchorAnswer(), 400e8);
        assertEq(a.anchorSetAt(), t0);
        vm.expectRevert(
            abi.encodeWithSignature(
                "DeviationTooHigh(int256,int256,uint16)", int256(440_04e6), int256(400e8), uint16(1000)
            )
        );
        a.updateAnswer(440_04e6);
        assertEq(a.latestAnswer(), 439_96e6);
        vm.stopPrank();
    }

    function test_window_exactBoundaryLandsAndNextUnitReverts() public {
        FengAggregator a = _agg10();
        vm.startPrank(relayer);
        a.updateAnswer(440e8);
        a.updateAnswer(360e8);
        vm.expectRevert();
        a.updateAnswer(440e8 + 1);
        vm.expectRevert();
        a.updateAnswer(360e8 - 1);
        vm.stopPrank();
    }

    function test_window_steppedUpThenCannotCompoundInsideWindow() public {
        FengAggregator a = _agg10();
        vm.startPrank(relayer);
        a.updateAnswer(439_99e6);
        vm.expectRevert();
        a.updateAnswer(483e8);
        vm.warp(block.timestamp + 30 minutes);
        vm.expectRevert();
        a.updateAnswer(483e8);
        vm.stopPrank();
    }

    function test_window_anchorMovesOnlyAfterWindow() public {
        FengAggregator a = _agg10();
        uint256 t0 = block.timestamp;
        vm.startPrank(relayer);
        vm.warp(t0 + 1 hours - 1);
        a.updateAnswer(430e8);
        assertEq(a.anchorAnswer(), 400e8);
        assertEq(a.anchorSetAt(), t0);
        vm.warp(t0 + 1 hours);
        a.updateAnswer(430e8);
        assertEq(a.anchorAnswer(), 430e8);
        assertEq(a.anchorSetAt(), t0 + 1 hours);
        a.updateAnswer(472e8);
        assertEq(a.anchorAnswer(), 430e8);
        vm.expectRevert();
        a.updateAnswer(473_01e6);
        vm.warp(t0 + 2 hours);
        a.updateAnswer(472e8);
        assertEq(a.anchorAnswer(), 472e8);
        vm.stopPrank();
    }

    function test_window_hourlyWalkIsGeometricNotUnbounded() public {
        FengAggregator a = _agg10();
        vm.startPrank(relayer);
        int256 p = 400e8;
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 1 hours);
            p = p * 110 / 100;
            a.updateAnswer(p);
        }
        vm.stopPrank();
        assertEq(a.latestAnswer(), 400e8 * 110 ** 5 / 100 ** 5);
    }

    function test_window_oneBlockWalkOfTenPushesReverts() public {
        FengAggregator a = _agg10();
        vm.startPrank(relayer);
        int256 p = 400e8;
        uint256 landed;
        bool reverted;
        for (uint256 i = 0; i < 10; i++) {
            p = p * 109 / 100;
            try a.updateAnswer(p) {
                landed++;
            } catch (bytes memory r) {
                bytes4 sel;
                assembly {
                    sel := mload(add(r, 32))
                }
                assertEq(sel, bytes4(keccak256("DeviationTooHigh(int256,int256,uint16)")));
                reverted = true;
                break;
            }
        }
        vm.stopPrank();
        assertTrue(reverted);
        assertEq(landed, 1);
        assertEq(a.anchorAnswer(), 400e8);
        assertLe(a.latestAnswer(), 440e8);
    }

    function testFuzz_window_neverLeavesBandWithinWindow(uint8 n, uint256 seed) public {
        FengAggregator a = _agg10();
        uint256 steps = bound(n, 1, 24);
        uint256 t0 = block.timestamp;
        vm.startPrank(relayer);
        for (uint256 i = 0; i < steps; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            vm.warp(t0 + (i * (1 hours - 1)) / steps);
            int256 ans = int256(bound(seed, 1, 1000e8));
            try a.updateAnswer(ans) {} catch {}
            int256 cur = a.latestAnswer();
            int256 d = cur > 400e8 ? cur - 400e8 : 400e8 - cur;
            assertLe(uint256(d) * 10_000, 400e8 * 1000);
            assertEq(a.anchorAnswer(), 400e8);
        }
        vm.stopPrank();
    }

    function test_shock_plus18Works_plus30Point01Reverts() public {
        FengAggregator a = _agg10();
        vm.prank(shocker);
        a.shockAnswer(472_00e6);
        assertEq(a.latestAnswer(), 472e8);
        assertEq(a.anchorAnswer(), 400e8);
        vm.prank(shocker);
        a.shockAnswer(520e8);
        vm.prank(shocker);
        vm.expectRevert(
            abi.encodeWithSignature("ShockTooHigh(int256,int256,uint16)", int256(520_01e6), int256(400e8), uint16(3000))
        );
        a.shockAnswer(520_01e6);
        vm.prank(shocker);
        vm.expectRevert(
            abi.encodeWithSignature("ShockTooHigh(int256,int256,uint16)", int256(279_99e6), int256(400e8), uint16(3000))
        );
        a.shockAnswer(279_99e6);
        vm.prank(shocker);
        a.shockAnswer(280e8);
    }

    function test_shock_doesNotMoveAnchorOrWindow() public {
        FengAggregator a = _agg10();
        uint256 t0 = a.anchorSetAt();
        vm.warp(t0 + 5 hours);
        vm.prank(shocker);
        a.shockAnswer(472e8);
        assertEq(a.anchorAnswer(), 400e8);
        assertEq(a.anchorSetAt(), t0);
    }

    function test_relayerCannotForceAnswer() public {
        FengAggregator a = _agg10();
        vm.prank(relayer);
        vm.expectRevert();
        a.forceAnswer(900e8);
        vm.prank(shocker);
        vm.expectRevert();
        a.forceAnswer(900e8);
        assertEq(a.latestAnswer(), 400e8);
    }

    function test_forceAnswer_restartsWindow() public {
        FengAggregator a = _agg10();
        vm.warp(block.timestamp + 3 hours);
        vm.prank(admin);
        a.forceAnswer(560e8);
        assertEq(a.anchorAnswer(), 560e8);
        assertEq(a.anchorSetAt(), block.timestamp);
        vm.prank(relayer);
        a.updateAnswer(615e8);
        assertEq(a.anchorAnswer(), 560e8);
        vm.prank(relayer);
        vm.expectRevert();
        a.updateAnswer(617e8);
    }

    function test_refresh_doesNotTouchAnchorOrWindow() public {
        FengAggregator a = _agg10();
        uint256 t0 = a.anchorSetAt();
        vm.warp(t0 + 4 hours);
        vm.prank(relayer);
        a.refresh();
        assertEq(a.anchorAnswer(), 400e8);
        assertEq(a.anchorSetAt(), t0);
    }

    function test_updateAnswer_deviationTooHigh() public {
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSignature(
                "DeviationTooHigh(int256,int256,uint16)", int256(460_01e6), int256(400e8), uint16(1500)
            )
        );
        agg.updateAnswer(460_01e6);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSignature(
                "DeviationTooHigh(int256,int256,uint16)", int256(339e8), int256(400e8), uint16(1500)
            )
        );
        agg.updateAnswer(339e8);
    }

    function test_updateAnswer_invalid() public {
        vm.startPrank(relayer);
        vm.expectRevert(abi.encodeWithSignature("InvalidAnswer(int256)", int256(0)));
        agg.updateAnswer(0);
        vm.expectRevert(abi.encodeWithSignature("InvalidAnswer(int256)", int256(-5)));
        agg.updateAnswer(-5);
        vm.stopPrank();
    }

    function test_updateAnswer_roleGated() public {
        vm.prank(rnd);
        vm.expectRevert();
        agg.updateAnswer(401e8);
        vm.prank(shocker);
        vm.expectRevert();
        agg.updateAnswer(401e8);
    }

    function test_noBackdating() public {
        vm.warp(block.timestamp + 5 hours);
        vm.prank(relayer);
        agg.updateAnswer(401e8);
        (,, uint256 upd) = _round();
        assertEq(upd, block.timestamp);
    }

    function test_shock_disabledByDefault() public {
        vm.prank(shocker);
        vm.expectRevert(abi.encodeWithSignature("ShockDisabled()"));
        agg.shockAnswer(450e8);
    }

    function test_shock_thenRestore() public {
        vm.prank(admin);
        agg.setShockEnabled(true);
        vm.prank(shocker);
        agg.shockAnswer(472e8);
        assertEq(agg.latestAnswer(), 472e8);
        assertEq(agg.anchorAnswer(), 400e8);
        vm.prank(relayer);
        agg.updateAnswer(405e8);
        assertEq(agg.latestAnswer(), 405e8);
        assertEq(agg.anchorAnswer(), 400e8);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(relayer);
        agg.updateAnswer(405e8);
        assertEq(agg.anchorAnswer(), 405e8);
    }

    function test_shock_boundsAndRole() public {
        vm.prank(admin);
        agg.setShockEnabled(true);
        vm.prank(shocker);
        vm.expectRevert(
            abi.encodeWithSignature("ShockTooHigh(int256,int256,uint16)", int256(520_01e6), int256(400e8), uint16(3000))
        );
        agg.shockAnswer(520_01e6);
        vm.prank(shocker);
        agg.shockAnswer(520e8);
        vm.prank(relayer);
        vm.expectRevert();
        agg.shockAnswer(450e8);
    }

    function test_shock_afterShockUpdateMeasuredAgainstAnchor() public {
        vm.prank(admin);
        agg.setShockEnabled(true);
        vm.prank(shocker);
        agg.shockAnswer(520e8);
        vm.prank(relayer);
        vm.expectRevert();
        agg.updateAnswer(520e8);
    }

    function test_refresh_keepsAnswerMovesTime() public {
        vm.prank(admin);
        agg.setShockEnabled(true);
        vm.prank(shocker);
        agg.shockAnswer(472e8);
        (uint80 id,,) = _round();
        vm.warp(block.timestamp + 2 hours);
        vm.prank(relayer);
        agg.refresh();
        (uint80 id2, int256 a, uint256 upd) = _round();
        assertEq(a, 472e8);
        assertEq(upd, block.timestamp);
        assertGt(id2, id);
        assertEq(agg.anchorAnswer(), 400e8);
        vm.prank(rnd);
        vm.expectRevert();
        agg.refresh();
    }

    function test_forceAnswer_reanchors() public {
        vm.prank(admin);
        agg.forceAnswer(1000e8);
        assertEq(agg.latestAnswer(), 1000e8);
        assertEq(agg.anchorAnswer(), 1000e8);
        vm.prank(relayer);
        vm.expectRevert();
        agg.forceAnswer(500e8);
        vm.prank(relayer);
        agg.updateAnswer(1100e8);
    }

    function test_setParams_capsAndRole() public {
        vm.startPrank(admin);
        agg.setParams(5000, 5000);
        assertEq(agg.maxDeviationBps(), 5000);
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        agg.setParams(5001, 3000);
        vm.expectRevert(abi.encodeWithSignature("InvalidParams()"));
        agg.setParams(1500, 5001);
        vm.stopPrank();
        vm.prank(rnd);
        vm.expectRevert();
        agg.setParams(100, 100);
        vm.prank(rnd);
        vm.expectRevert();
        agg.setShockEnabled(true);
    }

    function test_events() public {
        vm.prank(relayer);
        vm.expectEmit(true, false, false, false, address(agg));
        emit AnswerUpdated(410e8, 0, 0);
        agg.updateAnswer(410e8);
        vm.prank(admin);
        vm.expectEmit(true, false, true, false, address(agg));
        emit AnswerForced(900e8, 0, admin);
        agg.forceAnswer(900e8);
    }

    function testFuzz_updateAnswerBound(int256 answer) public {
        answer = bound(answer, 1, 1_000_000e8);
        int256 anchor = agg.anchorAnswer();
        int256 diff = answer > anchor ? answer - anchor : anchor - answer;
        bool ok = uint256(diff) * 10_000 <= uint256(anchor) * 1500;
        vm.prank(relayer);
        if (!ok) vm.expectRevert();
        agg.updateAnswer(answer);
        if (ok) assertEq(agg.latestAnswer(), answer);
    }
}
