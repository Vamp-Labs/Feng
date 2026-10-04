// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";

contract VectorsV2Test is DeployV2Helper {
    function _run(uint8 d)
        internal
        returns (IStrategyVaultV2 v, uint256 aliceShares, uint256 bobShares, uint256 aliceOut, uint256 previewAlice)
    {
        cfgUsdg = d;
        cfgStock = 18;
        _deployStack();
        (v,) = _fiftyFifty();
        aliceShares = _deposit(v, alice, 1000 * U);
        assertEq(IERC20(v.token()).balanceOf(alice), aliceShares);
        _setPrice(0, 440e8);
        bobShares = _deposit(v, bob, 500 * U);
        previewAlice = v.previewRedeem(aliceShares);
        vm.prank(alice);
        aliceOut = v.redeem(aliceShares, alice, alice, 0);
    }

    function test_vector_roundTrip_d6() public {
        cfgUsdg = 6;
        cfgStock = 18;
        _deployStack();
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 aliceShares = _deposit(v, alice, 1_000_000_000);
        assertEq(aliceShares, 999_000_998_000_000_000_000);
        assertEq(v.sharePrice(), 1_000_000);
        assertEq(v.totalAssetsUSDG(), 999_000_998);
        _setPrice(0, 440e8);
        assertEq(v.totalAssetsUSDG(), 1_048_951_048);
        assertEq(v.sharePrice(), 1_050_000);
        uint256 bobShares = _deposit(v, bob, 500_000_000);
        assertEq(bobShares, 475_714_759_070_294_789_189);
        assertEq(v.sharePrice(), 1_050_000);
        assertEq(v.previewRedeem(aliceShares), 1_048_951_049);
        vm.prank(alice);
        uint256 out = v.redeem(aliceShares, alice, alice, 0);
        assertEq(out, 1_047_902_098);
        assertEq(IERC20(usdg).balanceOf(alice), 1_047_902_098);
    }

    function test_vector_roundTrip_d18() public {
        cfgUsdg = 18;
        cfgStock = 18;
        _deployStack();
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 aliceShares = _deposit(v, alice, 1000 ether);
        assertEq(aliceShares, 999_000_999_000_999_000_650_000_000_000_000);
        assertEq(v.sharePrice(), 1_000_000);
        assertEq(v.inceptionSharePrice(), 1_000_000);
        _setPrice(0, 440e8);
        uint256 bobShares = _deposit(v, bob, 500 ether);
        assertEq(bobShares, 475_714_761_429_047_142_891_859_410_430_839);
        vm.prank(alice);
        uint256 out = v.redeem(aliceShares, alice, alice, 0);
        assertEq(out, 1_047_902_097_902_097_901_179);
    }

    function test_vector_d6_d18_sameValue() public {
        (,,, uint256 out6,) = _run(6);
        uint256 v6 = out6 * 1e12;
        setUp18();
        (,,, uint256 out18,) = _run(18);
        assertApproxEqRel(v6, out18, 1e-6 ether);
    }

    function setUp18() internal {
        delete stocks;
        delete feeds;
    }

    function test_vector_depth2_derivedFromChild() public {
        cfgUsdg = 6;
        cfgStock = 18;
        _deployStack();
        (IStrategyVaultV2 child, address childTok) = _fiftyFifty();
        (IStrategyVaultV2 parent,) = _nested(child, childTok);
        uint256 s = _deposit(parent, alice, 1000 * U);
        uint256 nav = parent.totalAssetsUSDG();
        assertLe(nav, 1000 * U);
        assertGe(nav, 1000 * U * 9970 / 10_000);
        assertApproxEqAbs(s, nav * _vS(), nav * _vS() / 1e6);
        assertApproxEqAbs(parent.sharePrice(), 1_000_000, 1);
        vm.prank(alice);
        uint256 out = parent.redeem(s, alice, alice, 0);
        assertGe(out, nav * 9960 / 10_000);
        assertLe(out, nav);
    }
}
