// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";

abstract contract ShareMathBase is DeployV2Helper {
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        (v,) = _fiftyFifty();
    }

    function testFuzz_roundTripAtConstantPrices(uint256 amt) public {
        amt = bound(amt, U, 1e6 * U);
        uint256 s = _deposit(v, alice, amt);
        vm.prank(alice);
        uint256 out = v.redeem(s, alice, alice, 0);
        uint256 grain = _valueOf(address(stocks[0]), 1, true);
        assertGe(out + 7 + 4 * grain, amt * (BPS - 2 * SPREAD) / BPS);
        assertLe(out, amt);
    }

    function testFuzz_sharesMatchIndependentFormula(uint256 first, uint256 second, uint256 moveBps) public {
        first = bound(first, U, 1e6 * U);
        second = bound(second, U / 10, 1e6 * U);
        moveBps = bound(moveBps, 0, 1400);
        _deposit(v, alice, first);
        _setPrice(0, int256(400e8 * (10_000 + moveBps) / 10_000));
        uint256 S = IERC20(v.token()).totalSupply();
        uint256 nbC = _navIndep(v, true);
        uint256 got = _deposit(v, bob, second);
        uint256 na = _navIndep(v, false);
        assertGt(na, nbC);
        assertEq(got, (na - nbC) * (S + _vS()) / (nbC + 1));
    }

    function testFuzz_previewRedeemInKindExact(uint256 amt, uint256 fracBps) public {
        amt = bound(amt, U, 1e6 * U);
        fracBps = bound(fracBps, 1, BPS);
        uint256 s = _deposit(v, alice, amt);
        _mintUsdg(address(v), U);
        uint256 shares = s * fracBps / BPS;
        uint256 S = IERC20(v.token()).totalSupply();
        uint256 b0 = IERC20(address(stocks[0])).balanceOf(address(v));
        uint256 idle = IERC20(usdg).balanceOf(address(v));
        vm.prank(alice);
        (, uint256[] memory a) = v.redeemInKind(shares, alice, alice);
        assertEq(a[0], b0 * shares / S);
        assertEq(a[2], idle * shares / S);
    }

    function testFuzz_sharePriceNotDownOnDeposit(uint256 amt) public {
        _deposit(v, alice, 1000 * U);
        _setPrice(0, 430e8);
        amt = bound(amt, U / 10, 1e6 * U);
        uint256 p0 = v.sharePrice();
        _deposit(v, bob, amt);
        assertGe(v.sharePrice() + 1 + p0 / 1e6, p0);
    }

    function testFuzz_sharePriceNotDownOnRedeem(uint256 frac) public {
        uint256 s = _deposit(v, alice, 1000 * U);
        _deposit(v, bob, 500 * U);
        _setPrice(0, 430e8);
        frac = bound(frac, 1, 100);
        uint256 p0 = v.sharePrice();
        vm.prank(alice);
        v.redeem(s * frac / 100, alice, alice, 0);
        assertGe(v.sharePrice() + 1 + p0 / 1e6, p0);
    }

    function testFuzz_inKindSharePriceExact(uint256 frac) public {
        uint256 s = _deposit(v, alice, 1000 * U);
        _deposit(v, bob, 500 * U);
        frac = bound(frac, 1, 100);
        uint256 p0 = v.sharePrice();
        vm.prank(alice);
        v.redeemInKind(s * frac / 100, alice, alice);
        assertApproxEqAbs(v.sharePrice(), p0, 1 + p0 / 1e12);
    }

    function testFuzz_depositNeverMintsAgainstZeroValue(uint256 amt) public {
        amt = bound(amt, 1, U);
        _mintUsdg(alice, amt);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(v), amt);
        try v.deposit(amt, alice, 0) returns (uint256 s) {
            assertLe(s, amt * _vS());
            assertGt(s, 0);
        } catch {}
        vm.stopPrank();
    }

    function testFuzz_previewDepositNeverBelowActualByMuch(uint256 first, uint256 second) public {
        first = bound(first, U, 1e6 * U);
        second = bound(second, U, 1e6 * U);
        _deposit(v, alice, first);
        uint256 A = v.totalAssetsUSDG();
        uint256 S = IERC20(v.token()).totalSupply();
        uint256 pv = v.previewDeposit(second);
        uint256 got = _deposit(v, bob, second);
        uint256 r = (S + _vS() + A) / (A + 1) + 1;
        assertLe(got, pv + r);
        assertLe(pv, got + 5 * r);
    }
}

contract ShareMath_U6_S18 is ShareMathBase {}

contract ShareMath_U18_S18 is ShareMathBase {
    constructor() {
        cfgUsdg = 18;
    }
}

contract ShareMath_U6_S8 is ShareMathBase {
    constructor() {
        cfgStock = 8;
    }
}

contract ShareMath_U18_S8 is ShareMathBase {
    constructor() {
        cfgUsdg = 18;
        cfgStock = 8;
    }
}
