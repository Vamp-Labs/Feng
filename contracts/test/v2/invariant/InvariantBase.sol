// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";

abstract contract InvariantBase is StdInvariant, Test {
    Handler internal h;
    uint8 internal dec;

    function _d() internal pure virtual returns (uint8);

    function setUp() public {
        dec = _d();
        h = new Handler(dec);
        targetContract(address(h));
        bytes4[] memory sels = new bytes4[](13);
        sels[0] = Handler.deposit.selector;
        sels[1] = Handler.depositInKind.selector;
        sels[2] = Handler.redeem.selector;
        sels[3] = Handler.redeemInKind.selector;
        sels[4] = Handler.roundTrip.selector;
        sels[5] = Handler.pushPrice.selector;
        sels[6] = Handler.warp.selector;
        sels[7] = Handler.rebalance.selector;
        sels[8] = Handler.checkpoint.selector;
        sels[9] = Handler.donate.selector;
        sels[10] = Handler.chaos.selector;
        sels[11] = Handler.refreshFeeds.selector;
        sels[12] = Handler.redeemInKindPlain.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sels}));
    }

    function _vaults() internal view returns (IStrategyVaultV2[2] memory v) {
        v[0] = h.vaultC();
        v[1] = h.vaultP();
    }

    function _independentNav(IStrategyVaultV2 v) internal view returns (uint256 nav) {
        nav = IERC20(h.usdgToken()).balanceOf(address(v));
        Constituent[] memory cs = v.getConstituents();
        for (uint256 i = 0; i < cs.length; i++) {
            uint256 bal = IERC20(cs[i].token).balanceOf(address(v));
            if (cs[i].isStrategyToken) {
                nav += IStrategyVaultV2(h.factoryOf().vaultOf(cs[i].token)).previewRedeem(bal);
            } else {
                (uint256 p,) = h.oracleOf().getPrice(cs[i].token);
                nav += bal * p / (10 ** (18 + 18 - dec));
            }
        }
    }

    function afterInvariant() public {
        emit log_named_uint("deposits", h.ghost_deposits());
        emit log_named_uint("redeems", h.ghost_redeems());
        emit log_named_uint("inKinds", h.ghost_inKinds());
        emit log_named_uint("rebalances", h.ghost_rebalances());
        emit log_named_uint("roundTrips", h.ghost_roundTrips());
        emit log_named_uint("checkpoints", h.ghost_checkpoints());
        emit log_named_uint("donations", h.ghost_donations());
        emit log_named_uint("expectedReverts", h.ghost_expectedReverts());
    }

    function invariant_I1_previewSumEqualsNav() public view {
        if (h.feedsBroken()) return;
        IStrategyVaultV2[2] memory vs = _vaults();
        for (uint256 k = 0; k < 2; k++) {
            IStrategyVaultV2 v = vs[k];
            uint256 nav = v.totalAssetsUSDG();
            uint256 S = IERC20(v.token()).totalSupply();
            if (S == 0) continue;
            assertEq(v.previewRedeem(S), nav);
            assertEq(nav, _independentNav(v));
            address[] memory hs = h.holders(k == 0);
            uint256 sum;
            for (uint256 i = 0; i < hs.length; i++) {
                sum += v.previewRedeem(IERC20(v.token()).balanceOf(hs[i]));
            }
            assertLe(sum, nav);
            assertGe(sum + hs.length + 1, nav);
        }
    }

    function invariant_I2_roundTrip() public view {
        assertFalse(
            h.ghost_i2Violation(),
            string.concat(
                "in=",
                vm.toString(h.ghost_i2Info(0)),
                " out=",
                vm.toString(h.ghost_i2Info(1)),
                " vault=",
                vm.toString(h.ghost_i2Info(2))
            )
        );
    }

    function invariant_I3_sharePriceNeverDrops() public view {
        assertFalse(h.ghost_i3Violation());
    }

    function invariant_I4_rebalanceCostBounded() public view {
        assertFalse(
            h.ghost_i4Violation(),
            string.concat(
                "nb=",
                vm.toString(h.ghost_i4Info(0)),
                " na=",
                vm.toString(h.ghost_i4Info(1)),
                " traded=",
                vm.toString(h.ghost_i4Info(2)),
                " vault=",
                vm.toString(h.ghost_i4Info(3))
            )
        );
    }

    function invariant_I5_inKindAlwaysWorks() public view {
        assertFalse(h.ghost_inKindWrong());
        assertFalse(h.ghost_redeemPaused());
        IStrategyVaultV2[2] memory vs = _vaults();
        for (uint256 k = 0; k < 2; k++) {
            uint256 S = IERC20(vs[k].token()).totalSupply();
            if (S == 0) continue;
            (address[] memory t, uint256[] memory a) = h.lensOf().previewRedeemInKind(address(vs[k]), S / 2 + 1);
            assertEq(t.length, a.length);
        }
    }

    function invariant_I6_noMintWithoutValue() public view {
        assertFalse(h.ghost_i6Violation(), "i6");
    }

    function invariant_supplyOnlyChangesByMintBurn() public view {
        assertFalse(h.ghost_supplyViolation(), "supply");
    }

    function invariant_I8_deskAccounting() public view {
        (uint256 funded, uint256 withdrawn, uint256 buyIn, uint256 sellOut) = h.deskOf().accounting();
        uint256 bal = IERC20(h.usdgToken()).balanceOf(address(h.deskOf()));
        assertGe(bal + withdrawn + sellOut, funded + buyIn);
        if (!h.ghost_deskDonated()) {
            assertGe(funded + buyIn, sellOut + withdrawn);
            assertEq(bal + withdrawn + sellOut, funded + buyIn);
        }
    }

    function invariant_noUnexpectedRevert() public view {
        assertFalse(h.ghost_unexpectedRevert());
    }

    function invariant_redeemNeverAboveNav() public view {
        assertFalse(h.ghost_redeemAboveNav());
    }

    function invariant_supplyEqualsSumBalances() public view {
        IStrategyVaultV2[2] memory vs = _vaults();
        for (uint256 k = 0; k < 2; k++) {
            address[] memory hs = h.holders(k == 0);
            uint256 sum;
            for (uint256 i = 0; i < hs.length; i++) {
                sum += IERC20(vs[k].token()).balanceOf(hs[i]);
            }
            assertEq(sum, IERC20(vs[k].token()).totalSupply());
        }
    }

    function invariant_noOpenApprovals() public view {
        IStrategyVaultV2[2] memory vs = _vaults();
        for (uint256 k = 0; k < 2; k++) {
            assertEq(IERC20(h.usdgToken()).allowance(address(vs[k]), address(h.deskOf())), 0);
            Constituent[] memory cs = vs[k].getConstituents();
            for (uint256 i = 0; i < cs.length; i++) {
                assertEq(IERC20(cs[i].token).allowance(address(vs[k]), address(h.deskOf())), 0);
                if (cs[i].isStrategyToken) {
                    assertEq(IERC20(cs[i].token).allowance(address(vs[k]), address(vs[0])), 0);
                    assertEq(IERC20(h.usdgToken()).allowance(address(vs[k]), address(vs[0])), 0);
                }
            }
        }
    }

    function invariant_depthAtMostTwo() public view {
        IStrategyVaultV2[2] memory vs = _vaults();
        assertEq(vs[0].depth(), 1);
        assertEq(vs[1].depth(), 2);
    }
}

contract Invariant6Dec is InvariantBase {
    function _d() internal pure override returns (uint8) {
        return 6;
    }
}

contract Invariant18Dec is InvariantBase {
    function _d() internal pure override returns (uint8) {
        return 18;
    }
}
