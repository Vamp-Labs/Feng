// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StrategyToken} from "../StrategyToken.sol";

contract StrategyTokenTest is Test {
    StrategyToken internal token;
    address internal vault = makeAddr("vault");
    address internal user = makeAddr("user");

    function setUp() public {
        token = new StrategyToken("Strategy", "STR", vault);
    }

    function test_mint_onlyVault() public {
        vm.prank(vault);
        token.mint(user, 100e18);
        assertEq(token.balanceOf(user), 100e18);
    }

    function test_mint_revertsForNonVault() public {
        vm.prank(user);
        vm.expectRevert(bytes("not vault"));
        token.mint(user, 100e18);
    }

    function test_burn_onlyVault() public {
        vm.prank(vault);
        token.mint(user, 100e18);

        vm.prank(vault);
        token.burn(user, 40e18);
        assertEq(token.balanceOf(user), 60e18);
    }

    function test_burn_revertsForNonVault() public {
        vm.prank(vault);
        token.mint(user, 100e18);

        vm.prank(user);
        vm.expectRevert(bytes("not vault"));
        token.burn(user, 40e18);
    }

    function test_vaultIsImmutableAndSet() public view {
        assertEq(token.vault(), vault);
    }
}
