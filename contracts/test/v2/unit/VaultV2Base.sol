// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IOracleDesk} from "../../../v2/interfaces/IOracleDesk.sol";
import {TestToken} from "../mocks/HostileTokens.sol";

abstract contract VaultV2Base is DeployV2Helper {
    IStrategyVaultV2 internal vault;
    address internal shareTok;

    function setUp() public virtual {
        _deployStack();
        (vault, shareTok) = _fiftyFifty();
    }

    function _seed(uint256 usdAmount) internal returns (uint256) {
        return _deposit(vault, alice, usdAmount * U);
    }

    function _ratio(uint256 S, uint256 A) internal view returns (uint256) {
        uint256 num = S + _vS();
        uint256 den = A + 1;
        return (num + den - 1) / den;
    }

    function test_inceptionSharePriceExact() public view {
        uint256 e = 18 > uint256(usdgDec) ? 18 - uint256(usdgDec) : 0;
        uint256 vS = 10 ** (e > 12 ? e : 12);
        assertEq(vault.inceptionSharePrice(), 1e18 / vS);
        assertEq(vault.sharePrice(), vault.inceptionSharePrice());
        assertEq(vault.usdgDecimals(), usdgDec);
    }

    function test_firstDepositKeepsInceptionPrice() public {
        _seed(1000);
        assertApproxEqAbs(vault.sharePrice(), vault.inceptionSharePrice(), 1);
    }

    function test_deposit_revertsOnStalePrice() public {
        _mintUsdg(alice, 100 * U);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(vault), 100 * U);
        vm.warp(block.timestamp + STALENESS + 1);
        vm.expectPartialRevert(_sel("StalePrice(address,uint256)"));
        vault.deposit(100 * U, alice, 0);
        vm.stopPrank();
    }

    function test_deposit_revertsWhenPaused() public {
        vm.prank(guardian);
        vault.pause();
        _mintUsdg(alice, 100 * U);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(vault), 100 * U);
        vm.expectPartialRevert(_sel("EnforcedPause()"));
        vault.deposit(100 * U, alice, 0);
        vm.stopPrank();
    }

    function test_deposit_minSharesEnforced() public {
        _seed(1000);
        _mintUsdg(bob, 100 * U);
        uint256 pv = vault.previewDeposit(100 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(vault), 100 * U);
        vm.expectPartialRevert(_sel("SlippageExceeded(uint256,uint256)"));
        vault.deposit(100 * U, bob, pv * 2);
        vm.stopPrank();
    }

    function test_deposit_zeroAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(0, alice, 0);
    }

    function test_deposit_dustLegsStayIdleAndCountInNav() public {
        uint256 amt = U / 100;
        uint256 shares = _deposit(vault, alice, amt);
        assertEq(IERC20(usdg).balanceOf(address(vault)), amt);
        assertEq(vault.totalAssetsUSDG(), amt);
        assertGt(shares, 0);
        assertEq(IERC20(address(stocks[0])).balanceOf(address(vault)), 0);
    }

    function test_deposit_previewWithinTolerance() public {
        _seed(1000);
        uint256 A = vault.totalAssetsUSDG();
        uint256 S = IERC20(shareTok).totalSupply();
        uint256 pv = vault.previewDeposit(500 * U);
        uint256 got = _deposit(vault, bob, 500 * U);
        uint256 r = _ratio(S, A);
        assertLe(got, pv + r);
        assertLe(pv, got + 4 * r);
    }

    function test_deposit_idleIncludedInNav() public {
        _seed(1000);
        uint256 before_ = vault.totalAssetsUSDG();
        _mintUsdg(address(vault), 50 * U);
        assertEq(vault.totalAssetsUSDG(), before_ + 50 * U);
        assertEq(vault.previewRedeem(IERC20(shareTok).totalSupply()), vault.totalAssetsUSDG());
    }

    function test_deposit_mintsToReceiver() public {
        _mintUsdg(alice, 100 * U);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(vault), 100 * U);
        uint256 s = vault.deposit(100 * U, bob, 0);
        vm.stopPrank();
        assertEq(IERC20(shareTok).balanceOf(bob), s);
        assertEq(IERC20(shareTok).balanceOf(alice), 0);
    }

    function test_depositInKind_valueAtOracle() public {
        _seed(100_000);
        TestToken t = stocks[0];
        uint256 amt = 10 ** (_stockDecimals() - 2);
        t.mint(bob, amt);
        uint256 pv = vault.previewDepositInKind(address(t), amt);
        uint256 navBefore = vault.totalAssetsUSDG();
        vm.startPrank(bob);
        t.approve(address(vault), amt);
        uint256 s = vault.depositInKind(address(t), amt, bob, 0);
        vm.stopPrank();
        assertEq(s, pv);
        assertEq(IERC20(shareTok).balanceOf(bob), s);
        uint256 v = _valueOf(address(t), amt, false);
        assertApproxEqAbs(vault.totalAssetsUSDG(), navBefore + v, 1);
    }

    function test_depositInKind_exceedsMaxWeightReverts() public {
        _seed(1000);
        TestToken t = stocks[0];
        uint256 amt = 10 ** _stockDecimals();
        t.mint(bob, amt * 10);
        vm.startPrank(bob);
        t.approve(address(vault), amt * 10);
        vm.expectPartialRevert(_sel("ExceedsMaxWeight(address)"));
        vault.depositInKind(address(t), amt * 10, bob, 0);
        vm.stopPrank();
    }

    function test_depositInKind_usdgReverts() public {
        _seed(1000);
        _mintUsdg(bob, 10 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(vault), 10 * U);
        vm.expectPartialRevert(_sel("TokenNotConstituent(address)"));
        vault.depositInKind(usdg, 10 * U, bob, 0);
        vm.stopPrank();
    }

    function test_depositInKind_nonConstituentReverts() public {
        _seed(1000);
        vm.prank(bob);
        vm.expectPartialRevert(_sel("TokenNotConstituent(address)"));
        vault.depositInKind(address(stocks[2]), 1, bob, 0);
    }

    function test_depositInKind_worksWithEmptyDesk() public {
        _seed(100_000);
        uint256 r = desk.reserveUsdg();
        vm.prank(admin);
        desk.withdrawReserve(admin, r);
        TestToken t = stocks[0];
        uint256 amt = 10 ** (_stockDecimals() - 2);
        t.mint(bob, amt);
        vm.startPrank(bob);
        t.approve(address(vault), amt);
        uint256 s = vault.depositInKind(address(t), amt, bob, 0);
        vm.stopPrank();
        assertGt(s, 0);
    }

    function test_redeem_equalsQuoteWithinDust() public {
        uint256 s = _seed(1000);
        uint256 q = lens.quoteRedeem(address(vault), s / 2);
        vm.prank(alice);
        uint256 out = vault.redeem(s / 2, alice, alice, 0);
        assertApproxEqAbs(out, q, 7);
        assertEq(IERC20(usdg).balanceOf(alice), out);
    }

    function test_redeem_quoteBelowPreview() public {
        uint256 s = _seed(1000);
        assertLe(lens.quoteRedeem(address(vault), s), vault.previewRedeem(s));
        assertEq(vault.previewRedeem(IERC20(shareTok).totalSupply()), vault.totalAssetsUSDG());
        assertEq(vault.previewRedeem(0), 0);
    }

    function test_redeem_revertsOnStale() public {
        uint256 s = _seed(1000);
        vm.warp(block.timestamp + STALENESS + 1);
        vm.prank(alice);
        vm.expectPartialRevert(_sel("StalePrice(address,uint256)"));
        vault.redeem(s, alice, alice, 0);
    }

    function test_redeem_neverPaused() public {
        uint256 s = _seed(1000);
        vm.prank(guardian);
        vault.pause();
        vm.prank(alice);
        uint256 out = vault.redeem(s, alice, alice, 0);
        assertGt(out, 0);
    }

    function test_redeem_delegatedNeedsAllowanceOfCaller() public {
        uint256 s = _seed(1000);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, s));
        vault.redeem(s, bob, alice, 0);
        vm.prank(alice);
        IERC20(shareTok).approve(bob, s);
        vm.prank(bob);
        uint256 out = vault.redeem(s, carol, alice, 0);
        assertGt(out, 0);
        assertEq(IERC20(usdg).balanceOf(carol), out);
        assertEq(IERC20(shareTok).balanceOf(alice), 0);
        assertEq(IERC20(shareTok).allowance(alice, bob), 0);
    }

    function test_redeem_vaultApprovalDoesNotAuthorizeCaller() public {
        uint256 s = _seed(1000);
        vm.prank(alice);
        IERC20(shareTok).approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, attacker, 0, s));
        vault.redeem(s, attacker, alice, 0);
        vm.prank(attacker);
        vm.expectRevert();
        vault.redeemInKind(s, attacker, alice);
        assertEq(IERC20(shareTok).balanceOf(alice), s);
    }

    function test_redeem_minUsdgOutEnforced() public {
        uint256 s = _seed(1000);
        vm.prank(alice);
        vm.expectPartialRevert(_sel("SlippageExceeded(uint256,uint256)"));
        vault.redeem(s, alice, alice, type(uint256).max);
    }

    function test_redeem_zeroSharesReverts() public {
        _seed(1000);
        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(0, alice, alice, 0);
    }

    function test_redeem_lastHolderDrainsEverything() public {
        uint256 s = _seed(1000);
        _mintUsdg(address(vault), 3 * U);
        vm.prank(alice);
        vault.redeem(s, alice, alice, 0);
        assertEq(IERC20(shareTok).totalSupply(), 0);
        assertEq(IERC20(usdg).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(stocks[0])).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(stocks[1])).balanceOf(address(vault)), 0);
    }

    function test_redeem_twoHoldersProRata() public {
        uint256 sa = _seed(1000);
        uint256 sb = _deposit(vault, bob, 3000 * U);
        uint256 pa = vault.previewRedeem(sa);
        uint256 pb = vault.previewRedeem(sb);
        assertLe(pa + pb, vault.totalAssetsUSDG());
        assertGe(pa + pb + 2, vault.totalAssetsUSDG());
    }

    function test_redeemInKind_returnsAllConstituentsAndIdle() public {
        uint256 s = _seed(1000);
        _mintUsdg(address(vault), 7 * U);
        uint256 S = IERC20(shareTok).totalSupply();
        uint256 b0 = IERC20(address(stocks[0])).balanceOf(address(vault));
        uint256 b1 = IERC20(address(stocks[1])).balanceOf(address(vault));
        uint256 idle = IERC20(usdg).balanceOf(address(vault));
        vm.prank(alice);
        (address[] memory toks, uint256[] memory amts) = vault.redeemInKind(s / 4, bob, alice);
        assertEq(toks.length, 3);
        assertEq(toks[0], address(stocks[0]));
        assertEq(toks[1], address(stocks[1]));
        assertEq(toks[2], usdg);
        assertEq(amts[0], b0 * (s / 4) / S);
        assertEq(amts[1], b1 * (s / 4) / S);
        assertEq(amts[2], idle * (s / 4) / S);
        assertEq(IERC20(address(stocks[0])).balanceOf(bob), amts[0]);
        assertEq(IERC20(usdg).balanceOf(bob), amts[2]);
        assertEq(IERC20(shareTok).balanceOf(alice), s - s / 4);
    }

    function test_redeemInKind_previewMatches() public {
        uint256 s = _seed(1000);
        (address[] memory pt, uint256[] memory pa) = lens.previewRedeemInKind(address(vault), s / 3);
        vm.prank(alice);
        (address[] memory t, uint256[] memory a) = vault.redeemInKind(s / 3, alice, alice);
        for (uint256 i = 0; i < t.length; i++) {
            assertEq(pt[i], t[i]);
            assertEq(pa[i], a[i]);
        }
    }

    function test_redeemInKindExcluding_skipsSliceAndIdle() public {
        uint256 s = _seed(1000);
        _mintUsdg(address(vault), 7 * U);
        uint256 b0 = IERC20(address(stocks[0])).balanceOf(address(vault));
        uint256 idle = IERC20(usdg).balanceOf(address(vault));
        vm.prank(alice);
        (, uint256[] memory amts) = vault.redeemInKindExcluding(s / 2, bob, alice, 1 | (1 << 2));
        assertEq(amts[0], 0);
        assertGt(amts[1], 0);
        assertEq(amts[2], 0);
        assertEq(IERC20(address(stocks[0])).balanceOf(address(vault)), b0);
        assertEq(IERC20(usdg).balanceOf(address(vault)), idle);
    }

    function test_redeemInKindExcluding_invalidMask() public {
        uint256 s = _seed(1000);
        vm.prank(alice);
        vm.expectPartialRevert(_sel("InvalidSkipMask()"));
        vault.redeemInKindExcluding(s, alice, alice, 1 << 3);
    }

    function test_rebalance_sellsBeforeBuys() public {
        (IStrategyVaultV2 v,) = _threeAsset();
        _deposit(v, alice, 10_000 * U);
        _setPrice(0, 440e8);
        _skewAndAge(3 days);
        (bool tb,) = v.rebalanceNeeded();
        assertTrue(tb);
        vm.recordLogs();
        vm.prank(keeper);
        v.executeRebalance();
        (uint256 sells, uint256 buys, bool ordered) = _legStats(vm.getRecordedLogs(), address(v));
        assertGe(sells, 1);
        assertGe(buys, 1);
        assertTrue(ordered);
    }

    function test_rebalance_deploysIdle() public {
        (IStrategyVaultV2 v,) = _threeAsset();
        _deposit(v, alice, 10_000 * U);
        _mintUsdg(address(v), 1000 * U);
        _skewAndAge(3 days);
        vm.prank(keeper);
        v.executeRebalance();
        uint256 T = v.totalAssetsUSDG();
        uint256 tol = T * 10 / BPS;
        uint256 minLeg = U / 100;
        assertLe(IERC20(usdg).balanceOf(address(v)), (tol > minLeg ? tol : minLeg) + 3);
    }

    function test_rebalance_skipsLegsInsideTolerance() public {
        _seed(10_000);
        _skewAndAge(7 days);
        vm.recordLogs();
        vault.executeRebalance();
        (uint256 sells, uint256 buys,) = _legStats(vm.getRecordedLogs(), address(vault));
        assertEq(sells + buys, 0);
    }

    function test_rebalance_thresholdUsesEffectiveMax() public {
        _seed(10_000);
        assertEq(vault.effectiveMaxWeightBps(0), 5010);
        _setPrice(0, 440e8);
        (bool tb, bool th) = vault.rebalanceNeeded();
        assertFalse(tb);
        assertTrue(th);
        vault.executeRebalance();
        (tb, th) = vault.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
    }

    function test_rebalance_thresholdFiresAboveMax() public {
        (IStrategyVaultV2 v,) = _threeAsset();
        _deposit(v, alice, 10_000 * U);
        _setPrice(0, 440e8);
        (bool tb, bool th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
        vm.prank(relayer);
        feeds[0].shockAnswer(512e8);
        (tb, th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertTrue(th);
        v.executeRebalance();
        (tb, th) = v.rebalanceNeeded();
        assertFalse(th);
    }

    function test_rebalance_timeBasedNoTradeStillAdvancesTimestamp() public {
        _seed(10_000);
        _skewAndAge(7 days);
        uint256 t = block.timestamp;
        vm.recordLogs();
        vault.executeRebalance();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(vault.lastRebalanceTimestamp(), t);
        assertEq(vault.lastCheckpointTimestamp(), t);
        assertGe(_indexOf(logs, address(vault), REBAL_TOPIC), 0);
        (bool tb,) = vault.rebalanceNeeded();
        assertFalse(tb);
    }

    function test_rebalance_emptyVaultNeverNeeded() public {
        _skewAndAge(30 days);
        (bool tb, bool th) = vault.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
        vm.expectPartialRevert(_sel("RebalanceNotNeeded()"));
        vault.executeRebalance();
    }

    function test_rebalance_notNeededReverts() public {
        _seed(1000);
        vm.expectPartialRevert(_sel("RebalanceNotNeeded()"));
        vault.executeRebalance();
    }

    function test_rebalance_pausedNotNeeded() public {
        _seed(1000);
        _skewAndAge(8 days);
        vm.prank(guardian);
        vault.pause();
        (bool tb, bool th) = vault.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
        vm.expectPartialRevert(_sel("EnforcedPause()"));
        vault.executeRebalance();
    }

    function test_rebalance_emitsCheckpointThenRebalanced() public {
        _seed(10_000);
        _skewAndAge(7 days);
        vm.recordLogs();
        vault.executeRebalance();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        int256 n = _indexOf(logs, address(vault), NAV_TOPIC);
        int256 r = _indexOf(logs, address(vault), REBAL_TOPIC);
        assertGe(n, 0);
        assertGt(r, n);
        assertEq(uint256(r), logs.length - 1);
    }

    function test_checkpoint_rateLimited() public {
        _seed(1000);
        vm.expectPartialRevert(_sel("CheckpointTooSoon(uint256)"));
        vault.checkpoint();
        vm.warp(block.timestamp + 30 minutes);
        _refreshAll();
        vm.recordLogs();
        vault.checkpoint();
        assertGe(_indexOf(vm.getRecordedLogs(), address(vault), NAV_TOPIC), 0);
        vm.expectPartialRevert(_sel("CheckpointTooSoon(uint256)"));
        vault.checkpoint();
    }

    function test_checkpoint_resetByDeposit() public {
        _seed(1000);
        vm.warp(block.timestamp + 31 minutes);
        _refreshAll();
        _deposit(vault, bob, 100 * U);
        vm.expectPartialRevert(_sel("CheckpointTooSoon(uint256)"));
        vault.checkpoint();
    }

    function test_checkpoint_revertsOnStale() public {
        _seed(1000);
        vm.warp(block.timestamp + 13 hours);
        vm.expectPartialRevert(_sel("StalePrice(address,uint256)"));
        vault.checkpoint();
    }

    function test_checkpoint_neverPaused() public {
        _seed(1000);
        vm.prank(guardian);
        vault.pause();
        vm.warp(block.timestamp + 31 minutes);
        _refreshAll();
        vault.checkpoint();
    }

    function test_pause_onlyGuardian() public {
        vm.prank(attacker);
        vm.expectPartialRevert(_sel("NotGuardian()"));
        vault.pause();
        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.paused());
        vm.prank(attacker);
        vm.expectPartialRevert(_sel("NotGuardian()"));
        vault.unpause();
        vm.prank(guardian);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_pause_blocksDepositInKindOnly() public {
        uint256 s = _seed(10_000);
        vm.prank(guardian);
        vault.pause();
        TestToken t = stocks[0];
        t.mint(bob, 1e6);
        vm.startPrank(bob);
        t.approve(address(vault), 1e6);
        vm.expectPartialRevert(_sel("EnforcedPause()"));
        vault.depositInKind(address(t), 1e6, bob, 0);
        vm.stopPrank();
        vm.prank(alice);
        vault.redeemInKind(s / 2, alice, alice);
    }

    function test_approvalsAlwaysZeroAfterCalls() public {
        uint256 s = _seed(10_000);
        _assertNoApprovals(vault);
        _setPrice(0, 440e8);
        vault.executeRebalance();
        _assertNoApprovals(vault);
        vm.prank(alice);
        vault.redeem(s / 3, alice, alice, 0);
        _assertNoApprovals(vault);
    }

    function _assertNoApprovals(IStrategyVaultV2 v) internal view {
        assertEq(IERC20(usdg).allowance(address(v), address(desk)), 0);
        for (uint256 i = 0; i < stocks.length; i++) {
            assertEq(stocks[i].allowance(address(v), address(desk)), 0);
        }
    }

    function test_weights_sumPlusIdleIs10000() public {
        _seed(10_000);
        _mintUsdg(address(vault), 1000 * U);
        uint16[] memory w = vault.weights();
        assertEq(w.length, 2);
        uint256 sum = uint256(w[0]) + w[1];
        assertLe(sum, BPS);
        uint256 T = vault.totalAssetsUSDG();
        uint256 idleBps = IERC20(usdg).balanceOf(address(vault)) * BPS / T;
        assertApproxEqAbs(BPS - sum, idleBps, 3);
    }

    function test_getConstituents_shape() public view {
        Constituent[] memory c = vault.getConstituents();
        assertEq(c.length, 2);
        assertEq(c[0].token, address(stocks[0]));
        assertEq(c[0].targetWeightBps, 5000);
        assertFalse(c[1].isStrategyToken);
        assertEq(vault.depth(), 1);
        assertEq(vault.guardian(), guardian);
        assertEq(vault.maxSlippageBps(), 100);
        assertEq(vault.maxPriceStaleness(), STALENESS);
        assertEq(vault.usdgToken(), usdg);
        assertEq(vault.venue(), address(desk));
        assertEq(vault.priceOracle(), address(oracle));
    }

    function test_hugeDepositNoOverflow() public {
        uint256 amt = 1e12 * U;
        _mintUsdg(alice, amt);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(vault), amt);
        uint256 s = vault.deposit(amt, alice, 0);
        vm.stopPrank();
        assertGt(s, 0);
        (, uint256[] memory a) = lens.previewRedeemInKind(address(vault), s);
        assertGt(a[0], 0);
    }

    function test_valueTokensRoundTripWithinOneUnit() public view {
        uint256 amt = 10 ** _stockDecimals();
        uint256 v = _valueOf(address(stocks[0]), amt, false);
        uint256 dec = _stockDecimals();
        uint256 p = _price18(address(stocks[0]));
        uint256 back = v * (10 ** (dec + 18 - usdgDec)) / p;
        assertLe(back, amt);
        uint256 vv = _valueOf(address(stocks[0]), back, false);
        assertApproxEqAbs(vv, v, 1);
    }

    function _nestedPair()
        internal
        returns (IStrategyVaultV2 child, address childTok, IStrategyVaultV2 parent, address parentTok)
    {
        child = vault;
        childTok = shareTok;
        (parent, parentTok) = _nested(child, childTok);
    }

    function test_nested_redeemUsdg_unwindsChild() public {
        (IStrategyVaultV2 child,, IStrategyVaultV2 parent,) = _nestedPair();
        uint256 s = _deposit(parent, alice, 10_000 * U);
        assertEq(parent.depth(), 2);
        assertGt(IERC20(address(child.token())).balanceOf(address(parent)), 0);
        uint256 q = lens.quoteRedeem(address(parent), s);
        vm.prank(alice);
        uint256 out = parent.redeem(s, alice, alice, 0);
        assertGt(out, 0);
        assertApproxEqRel(out, q, 1e15);
        assertEq(IERC20(address(child.token())).balanceOf(address(parent)), 0);
        assertEq(IERC20(address(child.token())).allowance(address(parent), address(child)), 0);
    }

    function test_nested_redeemInKind_childSharesNotUnwound() public {
        (IStrategyVaultV2 child, address childTok, IStrategyVaultV2 parent,) = _nestedPair();
        uint256 s = _deposit(parent, alice, 10_000 * U);
        uint256 cb = IERC20(childTok).balanceOf(address(parent));
        uint256 S = IERC20(parent.token()).totalSupply();
        vm.prank(alice);
        (address[] memory t, uint256[] memory a) = parent.redeemInKind(s / 2, alice, alice);
        assertEq(t[0], childTok);
        assertEq(a[0], cb * (s / 2) / S);
        assertEq(IERC20(childTok).balanceOf(alice), a[0]);
        assertEq(IERC20(address(stocks[0])).balanceOf(address(child)) > 0, true);
    }

    function test_nested_redeemUsdg_childFailureWrapsReason() public {
        (,, IStrategyVaultV2 parent,) = _nestedPair();
        uint256 s = _deposit(parent, alice, 10_000 * U);
        vm.prank(admin);
        desk.setToken(address(stocks[0]), IOracleDesk.Mode.Unsupported);
        vm.prank(alice);
        vm.expectPartialRevert(_sel("ChildRedeemFailed(address,bytes)"));
        parent.redeem(s, alice, alice, 0);
        vm.prank(alice);
        parent.redeemInKind(s, alice, alice);
    }

    function test_nested_staleChildBlocksParent() public {
        (,, IStrategyVaultV2 parent,) = _nestedPair();
        _deposit(parent, alice, 10_000 * U);
        vm.warp(block.timestamp + 13 hours);
        vm.startPrank(relayer);
        feeds[1].refresh();
        feeds[2].refresh();
        vm.stopPrank();
        _mintUsdg(bob, 100 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(parent), 100 * U);
        vm.expectPartialRevert(_sel("StalePrice(address,uint256)"));
        parent.deposit(100 * U, bob, 0);
        vm.stopPrank();
    }

    function test_priceStatus_recursesIntoChild() public {
        (,, IStrategyVaultV2 parent,) = _nestedPair();
        (bool fresh, uint256 oldest) = parent.priceStatus();
        assertTrue(fresh);
        assertEq(oldest, T0);
        vm.warp(block.timestamp + 13 hours);
        vm.startPrank(relayer);
        feeds[1].refresh();
        feeds[2].refresh();
        vm.stopPrank();
        (fresh, oldest) = parent.priceStatus();
        assertFalse(fresh);
        assertEq(oldest, T0);
        (fresh,) = vault.priceStatus();
        assertFalse(fresh);
    }

    function test_priceStatus_neverRevertsOnRemovedFeed() public {
        vm.prank(admin);
        oracle.removeFeed(address(stocks[0]));
        (bool fresh, uint256 o) = vault.priceStatus();
        assertFalse(fresh);
        assertEq(o, 0);
    }

    function test_nested_depositUsesChildMinShares() public {
        (IStrategyVaultV2 child,, IStrategyVaultV2 parent,) = _nestedPair();
        uint256 s = _deposit(parent, alice, 10_000 * U);
        assertGt(s, 0);
        uint256 childShares = IERC20(address(child.token())).balanceOf(address(parent));
        uint256 childVal = child.previewRedeem(childShares);
        assertApproxEqRel(childVal, 6000 * U * 999 / 1000, 5e15);
        assertEq(IERC20(usdg).allowance(address(parent), address(child)), 0);
    }

    function test_nested_parentThresholdAndRebalance() public {
        (,, IStrategyVaultV2 parent,) = _nestedPair();
        _deposit(parent, alice, 10_000 * U);
        _skewAndAge(7 days);
        vm.recordLogs();
        parent.executeRebalance();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGe(_indexOf(logs, address(parent), REBAL_TOPIC), 0);
    }
}
