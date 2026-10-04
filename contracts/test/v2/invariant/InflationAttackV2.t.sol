// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";

abstract contract InflationAttackV2Base is DeployV2Helper {
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        _mintUsdg(admin, 1e13 * U);
        vm.startPrank(admin);
        IERC20(usdg).approve(address(desk), type(uint256).max);
        desk.fundReserve(1e13 * U);
        vm.stopPrank();
        (v,) = _fiftyFifty();
    }

    function _attack(uint256 a, uint256 D, uint256 V, bool donateToken) internal {
        _mintUsdg(attacker, a);
        vm.startPrank(attacker);
        IERC20(usdg).approve(address(v), a);
        try v.deposit(a, attacker, 0) {}
        catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        uint256 attackerIn = a;
        if (donateToken) {
            uint256 tokens = D * (10 ** _stockDecimals()) / (400 * U);
            stocks[0].mint(address(v), tokens);
            attackerIn += _valueOf(address(stocks[0]), tokens, true);
        } else {
            _mintUsdg(address(v), D);
            attackerIn += D;
        }
        _mintUsdg(bob, V);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), V);
        try v.deposit(V, bob, 0) returns (uint256 vs_) {
            vm.stopPrank();
            assertGt(vs_, 0);
            vm.prank(bob);
            uint256 out = v.redeem(vs_, bob, bob, 0);
            assertGe(out + 3, V * 9975 / 10_000);
        } catch (bytes memory r) {
            vm.stopPrank();
            bytes4 s;
            assembly {
                s := mload(add(r, 32))
            }
            assertTrue(s == _sel("ZeroShares()") || s == _sel("NoValueAdded()"));
        }
        uint256 attackerShares = IERC20(v.token()).balanceOf(attacker);
        vm.prank(attacker);
        try v.redeem(attackerShares, attacker, attacker, 0) returns (uint256 got) {
            uint256 dust = 2 * (_valueOf(address(stocks[0]), 1, true) + _valueOf(address(stocks[1]), 1, true)) + 1;
            assertLe(got, attackerIn + dust);
        } catch {}
    }

    function testFuzz_I11_usdgDonation(uint256 a, uint256 D, uint256 V) public {
        a = bound(a, 2, 1e8 * U);
        D = bound(D, 0, 1e9 * U);
        V = bound(V, U, 1e6 * U);
        _attack(a, D, V, false);
    }

    function testFuzz_I11_constituentDonation(uint256 a, uint256 D, uint256 V) public {
        a = bound(a, 2, 1e8 * U);
        D = bound(D, 0, 1e9 * U);
        V = bound(V, U, 1e6 * U);
        _attack(a, D, V, true);
    }

    function test_I11_oneWeiClassScenario() public {
        _attack(2, 1e9 * U, 6000 * U, false);
    }

    function test_I11_oneWeiFirstDeposit() public {
        _attack(1, 591_054 * U, 6021 * U, false);
    }

    function test_I11_pythonModelCounterexampleNowSafe() public {
        _attack(528, 591_054 * U, 6021 * U, false);
    }
}

contract InflationAttackV2_6 is InflationAttackV2Base {}

contract InflationAttackV2_18 is InflationAttackV2Base {
    constructor() {
        cfgUsdg = 18;
    }
}

contract InflationAttackV2_6_S8 is InflationAttackV2Base {
    constructor() {
        cfgStock = 8;
    }
}

contract InflationAttackV2_18_S8 is InflationAttackV2Base {
    constructor() {
        cfgUsdg = 18;
        cfgStock = 8;
    }
}
