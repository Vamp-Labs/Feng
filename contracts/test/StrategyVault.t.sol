// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelper} from "./helpers/DeployHelper.sol";
import {StrategyVault} from "../StrategyVault.sol";
import {StrategyToken} from "../StrategyToken.sol";
import {Constituent, IStrategyVault} from "../interfaces/IStrategyVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StrategyVaultTest is DeployHelper {
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    StrategyVault internal soloVault;
    StrategyToken internal soloToken;

    function setUp() public {
        _deployCore();

        Constituent[] memory c = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (address vault, address token) = factory.createStrategy("Solo TSLA", "STSLA", c, 10_000, 7 days);
        soloVault = StrategyVault(vault);
        soloToken = StrategyToken(token);
    }

    function _approveAndDeposit(address user, uint256 amount) internal returns (uint256 shares) {
        _mintUsdg(user, amount);
        vm.startPrank(user);
        usdg.approve(address(soloVault), amount);
        shares = soloVault.deposit(amount, user);
        vm.stopPrank();
    }

    function test_deposit_mintsSharesAndAcquiresBasket() public {
        uint256 shares = _approveAndDeposit(alice, 1000e18);
        assertGt(shares, 0);
        assertEq(soloToken.balanceOf(alice), shares);

        // 1000 USDG @ 250 USD/TSLA => 4 TSLA held by the vault
        assertEq(tsla.balanceOf(address(soloVault)), 4e18);
        assertEq(usdg.balanceOf(address(soloVault)), 1000e18);
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(StrategyVault.ZeroAmount.selector);
        soloVault.deposit(0, alice);
    }

    function test_redeem_burnsSharesAndReturnsUsdg() public {
        uint256 shares = _approveAndDeposit(alice, 1000e18);

        vm.prank(alice);
        uint256 usdgOut = soloVault.redeem(shares, alice, alice);

        assertEq(soloToken.balanceOf(alice), 0);
        assertEq(usdg.balanceOf(alice), usdgOut);
        assertEq(tsla.balanceOf(address(soloVault)), 0);
    }

    function test_redeem_partialIsProRata() public {
        uint256 shares = _approveAndDeposit(alice, 1000e18);

        vm.prank(alice);
        soloVault.redeem(shares / 2, alice, alice);

        assertApproxEqAbs(tsla.balanceOf(address(soloVault)), 2e18, 1);
    }

    function test_redeem_delegatedRequiresAllowance() public {
        uint256 shares = _approveAndDeposit(alice, 1000e18);

        vm.prank(bob);
        vm.expectRevert();
        soloVault.redeem(shares, bob, alice);

        vm.prank(alice);
        soloToken.approve(address(soloVault), shares);

        vm.prank(bob);
        uint256 usdgOut = soloVault.redeem(shares, bob, alice);
        assertGt(usdgOut, 0);
        assertEq(usdg.balanceOf(bob), usdgOut);
    }

    function test_previewDeposit_matchesActualShares() public {
        uint256 amount = 500e18;
        _mintUsdg(alice, amount);
        uint256 preview = soloVault.previewDeposit(amount);

        vm.startPrank(alice);
        usdg.approve(address(soloVault), amount);
        uint256 actual = soloVault.deposit(amount, alice);
        vm.stopPrank();

        assertEq(preview, actual);
    }

    function test_rebalanceNeeded_timeBasedAfterInterval() public {
        (bool timeBased,) = soloVault.rebalanceNeeded();
        assertFalse(timeBased);

        vm.warp(block.timestamp + 7 days + 1);
        (bool timeBasedAfter,) = soloVault.rebalanceNeeded();
        assertTrue(timeBasedAfter);
    }

    function test_executeRebalance_revertsWhenNotNeeded() public {
        vm.expectRevert(StrategyVault.RebalanceNotNeeded.selector);
        soloVault.executeRebalance();
    }

    function test_executeRebalance_succeedsAndEmitsEvent() public {
        _approveAndDeposit(alice, 1000e18);
        vm.warp(block.timestamp + 7 days + 1);
        _refreshFeeds();

        vm.expectEmit(false, false, false, false, address(soloVault));
        emit IStrategyVault.Rebalanced(block.timestamp, true, false);
        soloVault.executeRebalance();
    }

    function test_thresholdBasedRebalance_multiAssetSkew() public {
        Constituent[] memory c = _twoAssetConstituents(address(tsla), 5000, address(amzn), 5000);
        vm.prank(creator);
        (address vault,) = factory.createStrategy("TA", "TA", c, 6000, 7 days);
        StrategyVault multi = StrategyVault(vault);

        _mintUsdg(alice, 1000e18);
        vm.startPrank(alice);
        usdg.approve(address(multi), 1000e18);
        multi.deposit(1000e18, alice);
        vm.stopPrank();

        (, bool thresholdBefore) = multi.rebalanceNeeded();
        assertFalse(thresholdBefore);

        vm.prank(admin);
        tslaFeed.updateAnswer(int256(1000e8));

        (, bool thresholdAfter) = multi.rebalanceNeeded();
        assertTrue(thresholdAfter);

        multi.executeRebalance();
        (, bool thresholdPost) = multi.rebalanceNeeded();
        assertFalse(thresholdPost);
    }

    function test_deposit_revertsOnStalePrice() public {
        vm.warp(block.timestamp + 25 hours);
        _mintUsdg(alice, 100e18);
        vm.startPrank(alice);
        usdg.approve(address(soloVault), 100e18);
        vm.expectRevert();
        soloVault.deposit(100e18, alice);
        vm.stopPrank();
    }

    function test_redeem_revertsOnStalePrice() public {
        uint256 shares = _approveAndDeposit(alice, 100e18);
        vm.warp(block.timestamp + 25 hours);

        vm.prank(alice);
        vm.expectRevert();
        soloVault.redeem(shares, alice, alice);
    }

    function test_executeRebalance_revertsOnStalePrice() public {
        _approveAndDeposit(alice, 1000e18);
        vm.warp(block.timestamp + 25 hours);
        vm.expectRevert();
        soloVault.executeRebalance();
    }

    // ---- depth-2 nested composability ----

    function test_depth2_deposit_holdsInnerStrategyTokenShares() public {
        (StrategyVault outerVault, StrategyToken innerToken) = _createDepth2();

        _mintUsdg(alice, 1000e18);
        vm.startPrank(alice);
        usdg.approve(address(outerVault), 1000e18);
        uint256 shares = outerVault.deposit(1000e18, alice);
        vm.stopPrank();

        assertGt(shares, 0);
        assertGt(innerToken.balanceOf(address(outerVault)), 0);
    }

    function test_depth2_totalAssetsUSDG_reflectsLiveNestedNav() public {
        (StrategyVault outerVault, StrategyToken innerToken) = _createDepth2();
        StrategyVault innerVault = StrategyVault(innerToken.vault());

        _mintUsdg(alice, 1000e18);
        vm.startPrank(alice);
        usdg.approve(address(outerVault), 1000e18);
        outerVault.deposit(1000e18, alice);
        vm.stopPrank();

        uint256 navBefore = outerVault.totalAssetsUSDG();

        vm.prank(admin);
        tslaFeed.updateAnswer(int256(500e8));

        uint256 navAfter = outerVault.totalAssetsUSDG();
        assertGt(navAfter, navBefore);

        vm.warp(block.timestamp + 7 days + 1);
        _refreshFeeds();
        innerVault.executeRebalance();

        uint256 navAfterRebalance = outerVault.totalAssetsUSDG();
        assertGt(navAfterRebalance, 0);
    }

    function test_depth2_redeem_returnsInnerStrategyTokenUnits() public {
        (StrategyVault outerVault, StrategyToken innerToken) = _createDepth2();

        _mintUsdg(alice, 1000e18);
        vm.startPrank(alice);
        usdg.approve(address(outerVault), 1000e18);
        uint256 shares = outerVault.deposit(1000e18, alice);

        uint256 innerBalanceBefore = innerToken.balanceOf(alice);
        outerVault.redeem(shares, alice, alice);
        vm.stopPrank();

        uint256 innerBalanceAfter = innerToken.balanceOf(alice);
        assertGt(innerBalanceAfter, innerBalanceBefore);
        assertEq(innerToken.balanceOf(address(outerVault)), 0);
    }

    function _createDepth2() internal returns (StrategyVault outerVault, StrategyToken innerToken) {
        Constituent[] memory c1 = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (, address depth1Token) = factory.createStrategy("Inner", "INR", c1, 10_000, 7 days);
        innerToken = StrategyToken(depth1Token);

        Constituent[] memory c2 = new Constituent[](1);
        c2[0] = Constituent({token: depth1Token, targetWeightBps: 10_000, isStrategyToken: true});
        vm.prank(creator);
        (address depth2Vault,) = factory.createStrategy("Outer", "OUT", c2, 10_000, 7 days);
        outerVault = StrategyVault(depth2Vault);
    }
}
