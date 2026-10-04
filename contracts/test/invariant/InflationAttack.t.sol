// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployHelper} from "../helpers/DeployHelper.sol";
import {StrategyVault} from "../../StrategyVault.sol";
import {StrategyToken} from "../../StrategyToken.sol";
import {Constituent} from "../../interfaces/IStrategyVault.sol";

/// @notice Exercises the vault's virtual-shares/decimals-offset inflation-attack mitigation
/// (ported from OpenZeppelin's ERC4626 technique) as an example-based scenario and as a
/// bounded fuzz test across attack sizes.
///
/// Note on this vault's specific attack surface: because deposit/redeem settle in USDG but
/// NAV (totalAssetsUSDG) is priced purely from the oracle-priced mock-stock basket the vault
/// itself mints/burns (never from its own raw USDG balance), a classic ERC4626 "donate the
/// underlying asset directly to the vault" attack does not skew the exchange rate here: raw
/// USDG sent straight to the vault (bypassing deposit()) is invisible to totalAssetsUSDG() and
/// is verified below to leave it unchanged. Mock stock tokens cannot be donated either, since
/// minting them is restricted to MINTER_ROLE (held only by vaults), so an outside attacker can
/// never hold spare stock tokens to donate. The mitigation still matters for the surface this
/// design does expose: a minimal first deposit skewing the totalSupply()/totalAssetsUSDG()
/// ratio so a later, normal-sized depositor's shares round down to zero. Both properties are
/// tested here.
contract InflationAttackTest is DeployHelper {
    address internal creator = makeAddr("creator");
    address internal attacker = makeAddr("attacker");
    address internal victim = makeAddr("victim");

    StrategyVault internal vault;
    StrategyToken internal token;

    function setUp() public {
        _deployCore();
        Constituent[] memory c = _singleAssetConstituents(address(tsla));
        vm.prank(creator);
        (address v, address t) = factory.createStrategy("Solo TSLA", "STSLA", c, 10_000, 7 days);
        vault = StrategyVault(v);
        token = StrategyToken(t);
    }

    /// @dev Fuzzes a minimal-first-deposit attack followed by a normal victim deposit across a
    /// wide range of sizes; the virtual-shares offset must keep the victim's minted shares
    /// (and their ability to redeem value back) strictly non-zero.
    function test_tinyFirstDeposit_neverZerosOutVictimShares(uint256 attackDeposit, uint256 victimDeposit) public {
        attackDeposit = bound(attackDeposit, 1, 1e12);
        victimDeposit = bound(victimDeposit, 1e6, 1_000_000e18);

        _mintUsdg(attacker, attackDeposit);
        vm.startPrank(attacker);
        usdg.approve(address(vault), attackDeposit);
        uint256 attackerShares = vault.deposit(attackDeposit, attacker);
        vm.stopPrank();
        assertGt(attackerShares, 0);

        _mintUsdg(victim, victimDeposit);
        vm.startPrank(victim);
        usdg.approve(address(vault), victimDeposit);
        uint256 victimShares = vault.deposit(victimDeposit, victim);
        vm.stopPrank();

        assertGt(victimShares, 0, "victim received zero shares: inflation attack succeeded");

        vm.prank(victim);
        uint256 victimRedeemed = vault.redeem(victimShares, victim, victim);
        assertGt(victimRedeemed, 0, "victim redeemed zero: inflation attack captured victim funds");
    }

    function test_rawUsdgDonation_doesNotAffectNav() public {
        _mintUsdg(attacker, 1);
        vm.startPrank(attacker);
        usdg.approve(address(vault), 1);
        vault.deposit(1, attacker);
        vm.stopPrank();

        uint256 navBefore = vault.totalAssetsUSDG();

        _mintUsdg(attacker, 1_000_000e18);
        vm.prank(attacker);
        usdg.transfer(address(vault), 1_000_000e18);

        uint256 navAfter = vault.totalAssetsUSDG();
        assertEq(navAfter, navBefore, "raw USDG donation unexpectedly changed NAV");
    }

    function test_tinyFirstDeposit_concreteScenario_victimGetsFairShares() public {
        uint256 attackDeposit = 1;
        uint256 victimDeposit = 1000e18;

        _mintUsdg(attacker, attackDeposit);
        vm.startPrank(attacker);
        usdg.approve(address(vault), attackDeposit);
        vault.deposit(attackDeposit, attacker);
        vm.stopPrank();

        _mintUsdg(victim, victimDeposit);
        vm.startPrank(victim);
        usdg.approve(address(vault), victimDeposit);
        uint256 victimShares = vault.deposit(victimDeposit, victim);
        vm.stopPrank();

        assertGt(victimShares, 0);

        vm.prank(victim);
        uint256 victimRedeemed = vault.redeem(victimShares, victim, victim);

        assertGt(victimRedeemed, victimDeposit / 2);
    }
}
