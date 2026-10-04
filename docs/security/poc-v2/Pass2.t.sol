// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../v2/helpers/DeployV2Helper.sol";
import {Constituent} from "../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2} from "../../v2/interfaces/IStrategyVaultV2.sol";
import {IOracleDesk} from "../../v2/interfaces/IOracleDesk.sol";
import {OracleDesk} from "../../v2/venue/OracleDesk.sol";
import {FengAggregator} from "../../v2/oracle/FengAggregator.sol";

// (1) aggregator: window alternation property
contract PoC2_AggregatorAlternation is DeployV2Helper {
    FengAggregator internal a;
    int256 internal lastAnchor;
    uint256 internal lastSet;
    uint256 internal moves;
    uint256 internal startTs;

    function setUp() public {
        vm.warp(T0);
        startTs = T0;
        vm.startPrank(admin);
        a = new FengAggregator(admin, 8, "X", 400e8, 1000, 3000);
        a.grantRole(a.UPDATER_ROLE(), relayer);
        a.grantRole(a.SHOCK_ROLE(), relayer);
        a.setShockEnabled(true);
        vm.stopPrank();
        lastAnchor = a.anchorAnswer();
        lastSet = a.anchorSetAt();
    }

    function _bound(int256 anchor, uint256 bps) internal pure returns (uint256) {
        return uint256(anchor) * bps / BPS;
    }

    function _dist(int256 x, int256 y) internal pure returns (uint256) {
        return x >= y ? uint256(x - y) : uint256(y - x);
    }

    // random sequence of update/refresh/shock/warp (no admin force): anchor moves at most once per hour, by at most D, latest within shock band
    function testFuzz_alternation(uint256 seed) public {
        for (uint256 i = 0; i < 60; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 op = seed % 5;
            int256 anchor0 = a.anchorAnswer();
            uint256 set0 = a.anchorSetAt();
            int256 px = int256(uint256(anchor0) * (7000 + (seed >> 8) % 6001) / 10_000);
            vm.startPrank(relayer);
            if (op == 0) {
                try a.updateAnswer(px) {} catch {}
            } else if (op == 1) {
                a.refresh();
            } else if (op == 2) {
                try a.shockAnswer(px) {} catch {}
            } else if (op == 3) {
                vm.warp(block.timestamp + (seed >> 16) % 2 hours);
            } else {
                int256 l = a.latestAnswer();
                try a.updateAnswer(l) {} catch {}
            }
            vm.stopPrank();
            int256 anchor1 = a.anchorAnswer();
            uint256 set1 = a.anchorSetAt();
            if (anchor1 != anchor0 || set1 != set0) {
                moves++;
                assertGe(block.timestamp, set0 + 1 hours, "anchor moved inside window");
                assertEq(set1, block.timestamp, "set stamp");
                assertLe(_dist(anchor1, anchor0), _bound(anchor0, 1000), "anchor step above D");
            }
            assertLe(set1, block.timestamp, "anchorSetAt in the future");
            assertGe(set1, set0, "anchorSetAt went back");
            assertLe(_dist(a.latestAnswer(), anchor1), _bound(anchor1, 3000), "latest outside shock band");
            assertGt(a.latestAnswer(), 0);
        }
        assertLe(moves, (block.timestamp - startTs) / 1 hours + 1, "more anchor moves than hours");
    }

    // shock, refresh, restore leaves the anchor sane
    function test_shockRefreshRestore() public {
        vm.startPrank(relayer);
        a.shockAnswer(472e8); // +18 percent
        vm.warp(block.timestamp + 90 minutes);
        a.refresh();
        assertEq(a.anchorAnswer(), 400e8);
        a.updateAnswer(400e8);
        assertEq(a.anchorAnswer(), 400e8);
        assertEq(a.latestAnswer(), 400e8);
        // anchor window already open, so the restore re-anchored: the next push uses the new set time
        assertEq(a.anchorSetAt(), block.timestamp);
        vm.stopPrank();
    }

    // the window does NOT bound a same-block round trip across the full band: low then high within one anchor
    function test_roundTripSpansBothSidesOfBand() public {
        vm.startPrank(relayer);
        a.updateAnswer(360e8); // -10 percent
        a.updateAnswer(440e8); // +10 percent, same anchor
        vm.stopPrank();
        assertEq(a.latestAnswer(), 440e8);
        assertEq(a.anchorAnswer(), 400e8);
    }

    // anchor sticks when only refresh is called: a real +25 percent over a day cannot be followed in one step
    function test_anchorSticksWithoutUpdates() public {
        vm.startPrank(relayer);
        for (uint256 i = 0; i < 24; i++) {
            vm.warp(block.timestamp + 1 hours);
            a.refresh();
        }
        vm.expectRevert();
        a.updateAnswer(500e8);
        a.updateAnswer(440e8);
        assertEq(a.anchorAnswer(), 440e8);
        vm.expectRevert();
        a.updateAnswer(484e8 + 1);
        vm.stopPrank();
    }
}

// (2) window round trip against the vault and desk (R-V2-03/F-01 residual after the window)
contract PoC2_RoundTrip is DeployV2Helper {
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        vm.prank(admin);
        desk.setMaxSwapUsdg(5000 * U);
        (v,) = _fiftyFifty();
        _deposit(v, alice, 1000 * U);
    }

    function test_oneTxRoundTripInsideWindow() public {
        _mintUsdg(relayer, 10_000 * U);
        uint256 reserve0 = desk.reserveUsdg();
        uint256 start = IERC20(usdg).balanceOf(relayer);
        vm.startPrank(relayer);
        IERC20(usdg).approve(address(v), type(uint256).max);
        uint256 sh;
        for (uint256 i = 0; i < 5; i++) {
            feeds[0].updateAnswer(340e8); // 400 -> 340 (-15 percent, the helper uses D = 1500)
            sh = v.deposit(7000 * U, relayer, 0);
            feeds[0].updateAnswer(460e8); // +15 percent, same anchor
            v.redeem(sh, relayer, relayer, 0);
            feeds[0].updateAnswer(400e8);
        }
        vm.stopPrank();
        uint256 end = IERC20(usdg).balanceOf(relayer);
        emit log_named_uint("relayer start (6dec)", start);
        emit log_named_uint("relayer end (6dec)", end);
        emit log_named_uint("desk reserve loss (6dec)", reserve0 - desk.reserveUsdg());
        assertGt(end, start);
    }
}

// (3) cap: exit paths and rebalance
contract PoC2_Cap is DeployV2Helper {
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        vm.prank(admin);
        desk.setMaxSwapUsdg(5000 * U);
        (v,) = _fiftyFifty();
        for (uint256 i = 0; i < 8; i++) {
            _deposit(v, alice, 10_000 * U); // each deposit buys two 5000 legs: exactly at the cap
        }
    }

    function test_capBlocksBigRedeemButNotInKind() public {
        uint256 sh = _shareToken(v).balanceOf(alice);
        vm.startPrank(alice);
        vm.expectRevert();
        v.redeem(sh, alice, alice, 0);
        (address[] memory toks, uint256[] memory amts) = v.redeemInKind(sh, alice, alice);
        vm.stopPrank();
        assertEq(toks.length, 3);
        assertGt(amts[0], 0);
        assertEq(_shareToken(v).balanceOf(alice), 0);
    }

    function test_capChunkedRedeemWorks() public {
        uint256 sh = _shareToken(v).balanceOf(alice);
        vm.startPrank(alice);
        v.redeem(sh / 16, alice, alice, 0); // 80k NAV / 16 = 5k, each leg 2.5k
        vm.stopPrank();
    }

    function test_capBricksRebalanceAboveThreshold() public {
        // NAV about 80k, 50/50. TSLA +30 percent via shock: weight 56.5 percent, excess about 5.2k at 80k
        vm.prank(relayer);
        feeds[0].shockAnswer(520e8);
        (, bool th) = v.rebalanceNeeded();
        assertTrue(th);
        vm.expectRevert();
        v.executeRebalance();
    }
}

// (4) flags with coarse (0-decimal) tokens
contract PoC2_FlagsCoarse is DeployV2Helper {
    function _stockDecimals() internal view virtual override returns (uint8) {
        return 0;
    }

    function setUp() public {
        _deployStack();
    }

    function test_coarseTokenFlagStaysTrue() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        _deposit(v, alice, 20_000 * U);
        vm.prank(relayer);
        feeds[0].shockAnswer(520e8);
        (bool tb, bool th) = v.rebalanceNeeded();
        emit log_named_uint("th before", th ? 1 : 0);
        if (th) {
            try v.executeRebalance() {} catch {
                emit log("executeRebalance reverted");
            }
            (tb, th) = v.rebalanceNeeded();
            emit log_named_uint("th after", th ? 1 : 0);
        }
        tb;
    }
}
