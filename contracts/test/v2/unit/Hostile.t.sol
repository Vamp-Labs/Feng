// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IStrategyFactoryV2} from "../../../v2/interfaces/IStrategyFactoryV2.sol";
import {StrategyFactoryV2} from "../../../v2/StrategyFactoryV2.sol";
import {
    ReentrantToken,
    BlocklistToken,
    FeeOnTransferToken,
    TestToken,
    RebasingToken,
    NoReturnToken,
    ReturnFalseToken
} from "../mocks/HostileTokens.sol";
import {HostileVenue} from "../mocks/HostileVenues.sol";

contract ReentrancyV2Test is DeployV2Helper {
    ReentrantToken internal rt;
    IStrategyVaultV2 internal v;
    bytes[] internal calls;

    function setUp() public {
        _deployStack();
        rt = new ReentrantToken("RT", "RT", 18);
        _newInventoryToken(address(rt), 50e8, 1e24);
        (v,) = _create("RE", _two(address(rt), 5000, address(stocks[0]), 5000), 5000, 1 days);
        _deposit(v, alice, 10_000 * U);
        _buildCalls();
    }

    function _buildCalls() internal {
        calls.push(abi.encodeCall(IStrategyVaultV2.deposit, (1e6, attacker, 0)));
        calls.push(abi.encodeCall(IStrategyVaultV2.depositInKind, (address(rt), 1, attacker, 0)));
        calls.push(abi.encodeCall(IStrategyVaultV2.redeem, (1, attacker, attacker, 0)));
        calls.push(abi.encodeCall(IStrategyVaultV2.redeemInKind, (1, attacker, attacker)));
        calls.push(abi.encodeCall(IStrategyVaultV2.redeemInKindExcluding, (1, attacker, attacker, 0)));
        calls.push(abi.encodeCall(IStrategyVaultV2.executeRebalance, ()));
        calls.push(abi.encodeCall(IStrategyVaultV2.checkpoint, ()));
        calls.push(abi.encodeCall(IStrategyVaultV2.previewRedeem, (1e18)));
        calls.push(abi.encodeCall(IStrategyVaultV2.totalAssetsUSDG, ()));
        calls.push(abi.encodeCall(IStrategyVaultV2.sharePrice, ()));
        calls.push(abi.encodeCall(IStrategyVaultV2.weights, ()));
        calls.push(abi.encodeCall(IStrategyVaultV2.previewDeposit, (1e6)));
        calls.push(abi.encodeCall(IStrategyVaultV2.rebalanceNeeded, ()));
    }

    function _arm() internal {
        rt.arm(address(v), calls);
    }

    function _assertAllGuarded() internal view {
        assertGt(rt.attempts(), 0);
        assertEq(rt.successes(), 0);
        assertEq(rt.failureCount(), rt.attempts());
        for (uint256 i = 0; i < rt.failureCount(); i++) {
            assertEq(rt.failureSelectors(i), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        }
    }

    function test_reentrancy_deposit() public {
        _arm();
        uint256 priceBefore = v.sharePrice();
        _deposit(v, bob, 1000 * U);
        _assertAllGuarded();
        assertGe(v.sharePrice() + 2, priceBefore);
    }

    function test_reentrancy_depositInKind() public {
        uint256 amt = 0.05 ether;
        rt.mint(bob, amt);
        _arm();
        vm.startPrank(bob);
        rt.approve(address(v), amt);
        v.depositInKind(address(rt), amt, bob, 0);
        vm.stopPrank();
        _assertAllGuarded();
    }

    function test_reentrancy_redeem() public {
        uint256 s = IERC20(v.token()).balanceOf(alice);
        _arm();
        vm.prank(alice);
        v.redeem(s / 2, alice, alice, 0);
        _assertAllGuarded();
    }

    function test_reentrancy_redeemInKind() public {
        uint256 s = IERC20(v.token()).balanceOf(alice);
        _arm();
        vm.prank(alice);
        v.redeemInKind(s / 2, alice, alice);
        _assertAllGuarded();
    }

    function test_reentrancy_redeemInKindExcluding() public {
        uint256 s = IERC20(v.token()).balanceOf(alice);
        _arm();
        vm.prank(alice);
        v.redeemInKindExcluding(s / 2, alice, alice, 2);
        _assertAllGuarded();
    }

    function test_reentrancy_executeRebalance() public {
        _setPrice(0, 460e8);
        _arm();
        v.executeRebalance();
        _assertAllGuarded();
    }

    function test_reentrancy_viewsOutsideExecutionStillWork() public view {
        v.previewRedeem(1e18);
        v.totalAssetsUSDG();
        v.weights();
    }

    function test_reentrancy_noValueExtracted() public {
        _arm();
        uint256 navBefore = v.totalAssetsUSDG();
        uint256 s = IERC20(v.token()).balanceOf(alice);
        vm.prank(alice);
        v.redeemInKind(s / 3, alice, alice);
        assertEq(IERC20(usdg).balanceOf(attacker), 0);
        assertEq(IERC20(v.token()).balanceOf(attacker), 0);
        assertEq(rt.balanceOf(attacker), 0);
        assertApproxEqAbs(v.totalAssetsUSDG(), navBefore - navBefore / 3, navBefore / 1e9 + 10);
    }
}

contract BlocklistV2Test is DeployV2Helper {
    BlocklistToken internal bt;
    IStrategyVaultV2 internal v;
    uint256 internal shares;

    function setUp() public {
        _deployStack();
        bt = new BlocklistToken("BLK", "BLK", 18);
        _newInventoryToken(address(bt), 50e8, 1e24);
        (v,) = _create("BL", _two(address(bt), 5000, address(stocks[1]), 5000), 5000, 1 days);
        shares = _deposit(v, alice, 10_000 * U);
    }

    function test_frozenVault_usdgRedeemAndInKindRevert_excludingExits() public {
        bt.setBlocked(address(v), true);
        vm.startPrank(alice);
        vm.expectRevert();
        v.redeem(shares / 2, alice, alice, 0);
        vm.expectRevert();
        v.redeemInKind(shares / 2, alice, alice);
        uint256 vaultBt = bt.balanceOf(address(v));
        (, uint256[] memory a) = v.redeemInKindExcluding(shares / 2, alice, alice, 1);
        vm.stopPrank();
        assertEq(a[0], 0);
        assertGt(a[1], 0);
        assertEq(bt.balanceOf(address(v)), vaultBt);
        assertEq(IERC20(v.token()).balanceOf(alice), shares - shares / 2);
        bt.setBlocked(address(v), false);
        vm.prank(alice);
        uint256 out = v.redeem(shares - shares / 2, alice, alice, 0);
        assertGt(out, 0);
    }

    function test_globalPause_depositAndRedeemRevert_excludingExits() public {
        bt.setPaused(true);
        _mintUsdg(bob, 100 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), 100 * U);
        vm.expectRevert();
        v.deposit(100 * U, bob, 0);
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert();
        v.redeem(shares, alice, alice, 0);
        v.redeemInKindExcluding(shares / 2, alice, alice, 1);
        vm.stopPrank();
    }

    function test_blockedReceiverRevertsAtomically() public {
        bt.setBlocked(alice, true);
        vm.prank(alice);
        vm.expectRevert();
        v.redeemInKind(shares / 2, alice, alice);
        assertEq(IERC20(v.token()).balanceOf(alice), shares);
    }
}

contract FeeUsdgV2Test is DeployV2Helper {
    IStrategyVaultV2 internal v;

    function _makeUsdg() internal override returns (address) {
        return address(new FeeOnTransferToken("USDG", "USDG", 6));
    }

    function setUp() public {
        _deployStack();
        (v,) = _fiftyFifty();
    }

    function test_deposit_feeOnTransferUsdgMintsFewerShares() public {
        _deposit(v, alice, 1000 * U);
        uint256 priceBefore = v.sharePrice();
        uint256 navBefore = v.totalAssetsUSDG();
        uint256 sBefore = IERC20(v.token()).totalSupply();
        FeeOnTransferToken(usdg).setFeeBps(30);
        uint256 shares = _deposit(v, bob, 1000 * U);
        uint256 bound = (_navIndep(v, false) - navBefore) * (sBefore + _vS()) / (navBefore + 1);
        assertLe(shares, bound + 1);
        uint256 honest = v.sharePrice() == 0 ? 0 : 1000 * U * 1e18 / priceBefore;
        assertLt(shares, honest * 9990 / 10_000);
        assertLe(v.previewRedeem(shares), 997 * U);
        assertGe(v.sharePrice() + 2, priceBefore);
    }

    function test_deposit_feeUsdgNeverOvermints_fuzz(uint256 fee, uint256 amt) public {
        fee = bound(fee, 0, 2000);
        bool tolerated = fee <= 50;
        amt = bound(amt, 10 * U, 100_000 * U);
        _deposit(v, alice, 1000 * U);
        uint256 navBefore = v.totalAssetsUSDG();
        uint256 sBefore = IERC20(v.token()).totalSupply();
        FeeOnTransferToken(usdg).setFeeBps(fee);
        _mintUsdg(bob, amt);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), amt);
        try v.deposit(amt, bob, 0) returns (uint256 shares) {
            vm.stopPrank();
            uint256 added = _navIndep(v, false) - navBefore;
            assertLe(shares, added * (sBefore + _vS()) / (navBefore + 1) + 1);
            assertLe(added, amt);
        } catch (bytes memory r) {
            vm.stopPrank();
            assertFalse(tolerated);
            bytes4 s;
            assembly {
                s := mload(add(r, 32))
            }
            assertTrue(s == _sel("VenueSlippage(uint256,uint256)") || s == _sel("SlippageExceeded(uint256,uint256)"));
        }
    }
}

contract HostileVenueV2Test is DeployV2Helper {
    HostileVenue internal hv;
    StrategyFactoryV2 internal f2;
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        hv = new HostileVenue(usdg);
        _mintUsdg(address(hv), 1e12 * U);
        uint256[2] memory px = [uint256(400), 250];
        for (uint256 i = 0; i < 2; i++) {
            stocks[i].mint(address(hv), 1e30);
            hv.configure(address(stocks[i]), 1e18 / (px[i] * U), px[i] * U);
        }
        f2 = new StrategyFactoryV2(
            address(registry), address(oracle), address(hv), usdg, guardian, address(deployer), STALENESS
        );
        bytes32 fr = registry.FACTORY_ROLE();
        vm.prank(admin);
        registry.grantRole(fr, address(f2));
        (v,) = _createWith(
            IStrategyFactoryV2(address(f2)),
            "HV",
            _two(address(stocks[0]), 5000, address(stocks[1]), 5000),
            5000,
            7 days,
            100
        );
    }

    function test_lyingAmountOutIsIgnored() public {
        hv.setLie(1e30);
        uint256 shares = _deposit(v, alice, 1000 * U);
        uint256 nav = _navIndep(v, false);
        assertEq(shares, nav * _vS());
        assertLe(nav, 1000 * U);
    }

    function test_shortDeliveryReducesShares() public {
        hv.setShortBps(50);
        uint256 shares = _deposit(v, alice, 1000 * U);
        uint256 nav = _navIndep(v, false);
        assertEq(shares, nav * _vS());
        assertLt(nav, 996 * U);
    }

    function test_shortDeliveryBeyondToleranceReverts() public {
        hv.setShortBps(500);
        _mintUsdg(alice, 1000 * U);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(v), 1000 * U);
        vm.expectPartialRevert(_sel("SlippageExceeded(uint256,uint256)"));
        v.deposit(1000 * U, alice, 0);
        vm.stopPrank();
    }

    function test_shortDeliveryOnRebalanceSellReverts() public {
        _deposit(v, alice, 1000 * U);
        _setPrice(0, 440e8);
        hv.configure(address(stocks[0]), 1e18 / (440 * U), 440 * U);
        hv.setShortBps(500);
        vm.expectPartialRevert(_sel("SlippageExceeded(uint256,uint256)"));
        v.executeRebalance();
    }

    function test_reentrantVenueBlocked() public {
        hv.setReenter(address(v), abi.encodeCall(IStrategyVaultV2.deposit, (1e6, attacker, 0)));
        _deposit(v, alice, 1000 * U);
        assertTrue(hv.reenterTried());
        assertFalse(hv.reenterOk());
    }
}

contract OddTokensV2Test is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function test_noReturnToken_fullCycle() public {
        NoReturnToken n = new NoReturnToken();
        _newInventoryToken(address(n), 100e8, 1e24);
        (IStrategyVaultV2 v,) = _create("NR", _two(address(n), 5000, address(stocks[1]), 5000), 5000, 1 days);
        uint256 s = _deposit(v, alice, 10_000 * U);
        assertGt(n.balanceOf(address(v)), 0);
        assertEq(n.allowance(address(v), address(desk)), 0);
        vm.prank(alice);
        uint256 out = v.redeem(s / 2, alice, alice, 0);
        assertGt(out, 0);
        vm.prank(alice);
        v.redeemInKind(s / 2, alice, alice);
        assertGt(n.balanceOf(alice), 0);
    }

    function test_returnFalseToken_revertsInsteadOfSilentLoss() public {
        ReturnFalseToken r = new ReturnFalseToken("RF", "RF", 18);
        _newInventoryToken(address(r), 100e8, 1e24);
        (IStrategyVaultV2 v,) = _create("RF", _two(address(r), 5000, address(stocks[1]), 5000), 5000, 1 days);
        uint256 s = _deposit(v, alice, 10_000 * U);
        r.setFailing(true);
        _mintUsdg(bob, 100 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), 100 * U);
        vm.expectRevert();
        v.deposit(100 * U, bob, 0);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert();
        v.redeemInKind(s / 2, alice, alice);
        assertEq(IERC20(v.token()).balanceOf(alice), s);
        vm.prank(alice);
        v.redeemInKindExcluding(s / 2, alice, alice, 1);
    }

    function test_rebasingToken_liveBalancesInNav() public {
        RebasingToken rb = new RebasingToken("RB", "RB", 18);
        _newInventoryToken(address(rb), 100e8, 1e24);
        (IStrategyVaultV2 v,) = _create("RB", _two(address(rb), 5000, address(stocks[1]), 5000), 5000, 1 days);
        _deposit(v, alice, 10_000 * U);
        uint256 nav0 = v.totalAssetsUSDG();
        uint256 bal0 = rb.balanceOf(address(v));
        rb.rebase(11_000);
        assertApproxEqRel(rb.balanceOf(address(v)), bal0 * 11 / 10, 1e12);
        uint256 nav1 = v.totalAssetsUSDG();
        assertGt(nav1, nav0);
        assertApproxEqRel(nav1 - nav0, nav0 * 5 / 100, 1e16);
        uint256 p = v.sharePrice();
        _deposit(v, bob, 1000 * U);
        assertGe(v.sharePrice() + 1 + p / 1e6, p);
    }
}
