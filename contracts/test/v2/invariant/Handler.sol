// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper, IMintLike} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IPriceOracleV2} from "../../../v2/interfaces/IPriceOracleV2.sol";
import {IStrategyFactoryV2} from "../../../v2/interfaces/IStrategyFactoryV2.sol";
import {StrategyLens} from "../../../v2/StrategyLens.sol";
import {IOracleDesk} from "../../../v2/interfaces/IOracleDesk.sol";

contract Handler is DeployV2Helper {
    IStrategyVaultV2 public vaultC;
    IStrategyVaultV2 public vaultP;
    address public tokenC;
    address public tokenP;

    address[] internal actors;

    bool public ghost_unexpectedRevert;
    bytes4 public ghost_lastUnexpected;
    bool public ghost_redeemPaused;
    bool public ghost_inKindWrong;
    bool public ghost_i2Violation;
    bool public ghost_i3Violation;
    bool public ghost_i4Violation;
    bool public ghost_i6Violation;
    bool public ghost_supplyViolation;
    bool public ghost_redeemAboveNav;
    bool public ghost_deskDonated;
    bool public feedsBroken;
    uint256[4] public ghost_i4Info;
    uint256[3] public ghost_i2Info;
    uint256 public ghost_expectedReverts;
    uint256 public ghost_deposits;
    uint256 public ghost_redeems;
    uint256 public ghost_inKinds;
    uint256 public ghost_rebalances;
    uint256 public ghost_roundTrips;
    uint256 public ghost_checkpoints;
    uint256 public ghost_donations;
    mapping(bytes4 => uint256) public expectedCount;

    constructor(uint8 d) {
        cfgUsdg = d;
        cfgStock = 18;
        _deployStack();
        address[] memory t = new address[](3);
        uint16[] memory w = new uint16[](3);
        t[0] = address(stocks[0]);
        t[1] = address(stocks[1]);
        t[2] = address(stocks[2]);
        w[0] = 4000;
        w[1] = 3500;
        w[2] = 2500;
        (vaultC, tokenC) = _create("CHILD", _cons(t, w), 4500, 1 days);
        Constituent[] memory c = new Constituent[](2);
        c[0] = Constituent({token: tokenC, targetWeightBps: 6000, isStrategyToken: true});
        c[1] = Constituent({token: address(stocks[2]), targetWeightBps: 4000, isStrategyToken: false});
        (vaultP, tokenP) = _create("PARENT", c, 6000, 1 days);
        actors.push(alice);
        actors.push(bob);
        actors.push(carol);
        actors.push(dave);
        actors.push(attacker);
        _deposit(vaultC, alice, 5000 * U);
        _deposit(vaultP, bob, 5000 * U);
    }

    function usdgToken() external view returns (address) {
        return usdg;
    }

    function deskOf() external view returns (IOracleDesk) {
        return IOracleDesk(address(desk));
    }

    function oracleOf() external view returns (IPriceOracleV2) {
        return IPriceOracleV2(address(oracle));
    }

    function factoryOf() external view returns (IStrategyFactoryV2) {
        return IStrategyFactoryV2(address(factory));
    }

    function lensOf() external view returns (StrategyLens) {
        return lens;
    }

    function holders(bool forChild) external view returns (address[] memory h) {
        h = new address[](forChild ? actors.length + 1 : actors.length);
        for (uint256 i = 0; i < actors.length; i++) {
            h[i] = actors[i];
        }
        if (forChild) h[actors.length] = address(vaultP);
    }

    function pick(uint256 seed) public view returns (IStrategyVaultV2) {
        return seed % 2 == 0 ? vaultC : vaultP;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _supply(IStrategyVaultV2 v) internal view returns (uint256) {
        return IERC20(v.token()).totalSupply();
    }

    function _isExpected(bytes4 s) internal pure returns (bool) {
        return s == _sel("EnforcedPause()") || s == _sel("StalePrice(address,uint256)")
            || s == _sel("SlippageExceeded(uint256,uint256)") || s == _sel("InsufficientLiquidity(address)")
            || s == _sel("RebalanceNotNeeded()") || s == _sel("CheckpointTooSoon(uint256)") || s == _sel("ZeroShares()")
            || s == _sel("ZeroAssets()") || s == _sel("NoValueAdded()") || s == _sel("ExceedsMaxWeight(address)")
            || s == _sel("ChildRedeemFailed(address,bytes)") || s == _sel("FeedNotSet(address)")
            || s == _sel("UnsupportedPair(address,address)") || s == _sel("NotConfigured(address)")
            || s == _sel("ZeroAmount()") || s == _sel("VenueSlippage(uint256,uint256)");
    }

    function _selOf(bytes memory r) internal pure returns (bytes4 s) {
        if (r.length >= 4) {
            assembly {
                s := mload(add(r, 32))
            }
        }
    }

    function _record(bytes memory r) internal {
        bytes4 s = _selOf(r);
        if (_isExpected(s)) {
            ghost_expectedReverts++;
            expectedCount[s]++;
        } else {
            ghost_unexpectedRevert = true;
            ghost_lastUnexpected = s;
        }
    }

    function _recordStrict(bytes memory r) internal {
        bytes4 s = _selOf(r);
        if (s == _sel("EnforcedPause()")) ghost_redeemPaused = true;
        ghost_unexpectedRevert = true;
        ghost_lastUnexpected = s;
    }

    function deposit(uint256 actorSeed, uint256 vSeed, uint256 amount) external {
        IStrategyVaultV2 v = pick(vSeed);
        address a = _actor(actorSeed);
        amount = bound(amount, U, 200_000 * U);
        _mintUsdg(a, amount);
        uint256 minShares;
        try v.previewDeposit(amount) returns (uint256 pv) {
            minShares = pv * 99 / 100;
        } catch (bytes memory r) {
            _record(r);
            return;
        }
        uint256 S = _supply(v);
        uint256 nbC = feedsBroken ? 0 : _navIndep(v, true);
        uint256 price = feedsBroken ? 0 : v.sharePrice();
        vm.startPrank(a);
        IERC20(usdg).approve(address(v), amount);
        try v.deposit(amount, a, minShares) returns (uint256 sh) {
            vm.stopPrank();
            ghost_deposits++;
            if (_supply(v) != S + sh) ghost_supplyViolation = true;
            if (!feedsBroken) {
                uint256 na = _navIndep(v, false);
                if (na <= nbC || sh > (na - nbC) * (S + _vS()) / (nbC + 1)) ghost_i6Violation = true;
                uint256 p2 = v.sharePrice();
                if (S >= 1e18 && p2 + 1 + price / 1e6 < price) ghost_i3Violation = true;
            }
        } catch (bytes memory r) {
            vm.stopPrank();
            _record(r);
        }
    }

    function depositInKind(uint256 actorSeed, uint256 vSeed, uint256 assetSeed, uint256 amount) external {
        IStrategyVaultV2 v = pick(vSeed);
        address a = _actor(actorSeed);
        uint256 idx = v == vaultC ? assetSeed % 3 : 2;
        TestTokenLike t = TestTokenLike(address(stocks[idx]));
        amount = bound(amount, 10 ** 15, 5 * 10 ** 18);
        t.mint(a, amount);
        uint256 S = _supply(v);
        uint256 nbC = feedsBroken ? 0 : _navIndep(v, true);
        vm.startPrank(a);
        IERC20(address(t)).approve(address(v), amount);
        try v.depositInKind(address(t), amount, a, 0) returns (uint256 sh) {
            vm.stopPrank();
            ghost_deposits++;
            if (_supply(v) != S + sh) ghost_supplyViolation = true;
            if (!feedsBroken) {
                if (sh > _valueOf(address(t), amount, false) * (S + _vS()) / (nbC + 1)) ghost_i6Violation = true;
            }
        } catch (bytes memory r) {
            vm.stopPrank();
            _record(r);
        }
    }

    function redeem(uint256 actorSeed, uint256 vSeed, uint256 frac) external {
        IStrategyVaultV2 v = pick(vSeed);
        address a = _actor(actorSeed);
        uint256 bal = IERC20(v.token()).balanceOf(a);
        if (bal == 0) return;
        uint256 shares = bal * bound(frac, 1, 100) / 100;
        if (shares == 0) return;
        uint256 minOut;
        try lens.quoteRedeem(address(v), shares) returns (uint256 q) {
            minOut = q * 99 / 100;
        } catch (bytes memory r) {
            _record(r);
            return;
        }
        uint256 S = _supply(v);
        uint256 price = feedsBroken ? 0 : v.sharePrice();
        uint256 pv = feedsBroken ? 0 : v.previewRedeem(shares);
        vm.prank(a);
        try v.redeem(shares, a, a, minOut) returns (uint256 out) {
            ghost_redeems++;
            if (_supply(v) != S - shares) ghost_supplyViolation = true;
            if (!feedsBroken) {
                if (out > pv + 8) ghost_redeemAboveNav = true;
                uint256 p2 = _supply(v) >= 1e18 && S >= 1e18 ? v.sharePrice() : price;
                if (p2 + 1 + price / 1e6 < price) ghost_i3Violation = true;
            }
        } catch (bytes memory r) {
            if (_selOf(r) == _sel("EnforcedPause()")) ghost_redeemPaused = true;
            _record(r);
        }
    }

    function _balancesOf(IStrategyVaultV2 v) internal view returns (uint256[] memory out) {
        Constituent[] memory cs = v.getConstituents();
        out = new uint256[](cs.length + 1);
        for (uint256 i = 0; i < cs.length; i++) {
            out[i] = IERC20(cs[i].token).balanceOf(address(v));
        }
        out[cs.length] = IERC20(usdg).balanceOf(address(v));
    }

    function _checkInKind(uint256[] memory before_, uint256[] memory amts, uint256 shares, uint256 S, uint256 mask)
        internal
    {
        for (uint256 i = 0; i < before_.length; i++) {
            uint256 expect_ = (mask >> i) & 1 == 1 ? 0 : before_[i] * shares / S;
            if (amts[i] != expect_) ghost_inKindWrong = true;
        }
    }

    function redeemInKind(uint256 actorSeed, uint256 vSeed, uint256 frac, uint256 mask, bool excluding) external {
        IStrategyVaultV2 v = pick(vSeed);
        address a = _actor(actorSeed);
        uint256 bal = IERC20(v.token()).balanceOf(a);
        if (bal == 0) return;
        uint256 shares = bal * bound(frac, 1, 100) / 100;
        if (shares == 0) return;
        uint256[] memory before_ = _balancesOf(v);
        uint256 S = _supply(v);
        mask = excluding ? mask % (1 << before_.length) : 0;
        vm.prank(a);
        try v.redeemInKindExcluding(shares, a, a, mask) returns (address[] memory, uint256[] memory amts) {
            ghost_inKinds++;
            _checkInKind(before_, amts, shares, S, mask);
            if (_supply(v) != S - shares) ghost_supplyViolation = true;
        } catch (bytes memory r) {
            _recordStrict(r);
        }
        try lens.previewRedeemInKind(address(v), 1e18) {}
        catch (bytes memory r) {
            _recordStrict(r);
        }
    }

    function redeemInKindPlain(uint256 actorSeed, uint256 vSeed, uint256 frac) external {
        IStrategyVaultV2 v = pick(vSeed);
        address a = _actor(actorSeed);
        uint256 bal = IERC20(v.token()).balanceOf(a);
        if (bal == 0) return;
        uint256 shares = bal * bound(frac, 1, 100) / 100;
        if (shares == 0) return;
        uint256[] memory before_ = _balancesOf(v);
        uint256 S = _supply(v);
        vm.prank(a);
        try v.redeemInKind(shares, a, a) returns (address[] memory, uint256[] memory amts) {
            ghost_inKinds++;
            _checkInKind(before_, amts, shares, S, 0);
            if (_supply(v) != S - shares) ghost_supplyViolation = true;
        } catch (bytes memory r) {
            _recordStrict(r);
        }
    }

    function roundTrip(uint256 actorSeed, uint256 vSeed, uint256 amount) external {
        IStrategyVaultV2 v = pick(vSeed);
        address a = _actor(actorSeed);
        amount = bound(amount, 10 * U, 100_000 * U);
        if (v.paused() || feedsBroken) return;
        (bool fresh,) = v.priceStatus();
        if (!fresh) return;
        uint256 before_ = IERC20(v.token()).balanceOf(a);
        _mintUsdg(a, amount);
        vm.startPrank(a);
        IERC20(usdg).approve(address(v), amount);
        try v.deposit(amount, a, 0) returns (uint256 sh) {
            try v.redeem(sh, a, a, 0) returns (uint256 out) {
                vm.stopPrank();
                ghost_roundTrips++;
                uint256 loss = v == vaultC ? 2 * SPREAD : 2 * (SPREAD + 100);
                if (out + 2 * 6 + 3 < amount * (BPS - loss) / BPS) {
                    ghost_i2Violation = true;
                    ghost_i2Info = [amount, out, v == vaultC ? 1 : 2];
                }
            } catch (bytes memory r) {
                vm.stopPrank();
                _record(r);
            }
        } catch (bytes memory r) {
            vm.stopPrank();
            _record(r);
        }
        before_;
    }

    function pushPrice(uint256 assetSeed, uint256 deltaSeed) external {
        if (feedsBroken) return;
        uint256 i = assetSeed % 3;
        int256 anchor = feeds[i].anchorAnswer();
        int256 delta = int256(bound(deltaSeed, 0, 2000)) - 1000;
        int256 answer = anchor * (10_000 + delta) / 10_000;
        vm.prank(relayer);
        try feeds[i].updateAnswer(answer) {}
        catch (bytes memory r) {
            _recordStrict(r);
        }
    }

    function refreshFeeds() external {
        _refreshAll();
    }

    function warp(uint256 dt, bool keepFresh) external {
        vm.warp(block.timestamp + bound(dt, 0, 2 days));
        if (keepFresh) _refreshAll();
    }

    function rebalance(uint256 vSeed) external {
        IStrategyVaultV2 v = pick(vSeed);
        address[] memory due = engine.checkUpkeep();
        bool listed;
        for (uint256 i = 0; i < due.length; i++) {
            if (due[i] == address(v)) listed = true;
        }
        if (!listed) return;
        uint256 S = _supply(v);
        uint256 navBefore = feedsBroken ? 0 : v.totalAssetsUSDG();
        vm.recordLogs();
        vm.prank(keeper);
        try engine.performRebalance(address(v)) {
            ghost_rebalances++;
            Vm.Log[] memory logs = vm.getRecordedLogs();
            if (_supply(v) != S) ghost_supplyViolation = true;
            if (feedsBroken) return;
            uint256 traded;
            for (uint256 i = 0; i < logs.length; i++) {
                if (logs[i].topics[0] == LEG_TOPIC) {
                    (, uint256 usdgAmt,) = abi.decode(logs[i].data, (bool, uint256, uint256));
                    traded += usdgAmt;
                }
            }
            uint256 navAfter = v.totalAssetsUSDG();
            uint256 factor = v == vaultC ? 1 : 2;
            bool bad = navAfter > navBefore + 8;
            if (navBefore > navAfter && navBefore - navAfter > factor * (traded * SPREAD / (BPS - SPREAD)) + 8 * factor)
            {
                bad = true;
            }
            if (bad) {
                ghost_i4Violation = true;
                ghost_i4Info = [navBefore, navAfter, traded, v == vaultC ? 1 : 2];
            }
        } catch (bytes memory r) {
            vm.getRecordedLogs();
            _record(r);
        }
    }

    function checkpoint(uint256 vSeed) external {
        IStrategyVaultV2 v = pick(vSeed);
        uint256 S = _supply(v);
        try v.checkpoint() {
            ghost_checkpoints++;
        } catch (bytes memory r) {
            _record(r);
        }
        address[] memory list = new address[](2);
        list[0] = address(vaultC);
        list[1] = address(vaultP);
        engine.checkpoint(list);
        if (_supply(v) != S) ghost_supplyViolation = true;
    }

    function donate(uint256 vSeed, uint256 kind, uint256 amount) external {
        IStrategyVaultV2 v = pick(vSeed);
        uint256 S = _supply(v);
        kind = kind % 4;
        if (kind == 0) {
            amount = bound(amount, 1, 100_000 * U);
            _mintUsdg(address(v), amount);
        } else if (kind == 1 || kind == 2) {
            amount = bound(amount, 1, 10 ** 18);
            uint256 idx = v == vaultC ? kind - 1 : 2;
            TestTokenLike(address(stocks[idx])).mint(address(v), amount);
        } else {
            amount = bound(amount, 1, 100_000 * U);
            _mintUsdg(address(desk), amount);
            ghost_deskDonated = true;
        }
        ghost_donations++;
        if (_supply(v) != S) ghost_supplyViolation = true;
    }

    function chaos(uint256 mode, uint256 seed) external {
        mode = mode % 7;
        if (mode == 0) {
            vm.warp(block.timestamp + STALENESS + 1);
        } else if (mode == 1) {
            address tk = address(stocks[seed % 3]);
            if (desk.mode(tk) != IOracleDesk.Mode.Unsupported) {
                vm.prank(admin);
                desk.setToken(tk, IOracleDesk.Mode.Unsupported);
            }
        } else if (mode == 2) {
            uint256 r = desk.reserveUsdg();
            if (r > 0) {
                vm.prank(admin);
                desk.withdrawReserve(admin, r);
            }
        } else if (mode == 3) {
            vm.startPrank(admin);
            for (uint256 i = 0; i < 3; i++) {
                desk.setToken(address(stocks[i]), IOracleDesk.Mode.Mint);
                if (!oracle.isSupported(address(stocks[i]))) oracle.setFeed(address(stocks[i]), address(feeds[i]));
            }
            uint256 bal = IERC20(usdg).balanceOf(admin);
            if (desk.reserveUsdg() < 1_000_000 * U) {
                _fund(1_000_000 * U);
            }
            bal;
            vm.stopPrank();
            feedsBroken = false;
            _refreshAll();
        } else if (mode == 4) {
            IStrategyVaultV2 pv = pick(seed);
            bool isPaused = pv.paused();
            vm.prank(guardian);
            if (isPaused) {
                pv.unpause();
            } else {
                pv.pause();
            }
        } else if (mode == 5) {
            address victim = address(stocks[seed % 3]);
            if (oracle.isSupported(victim)) {
                vm.prank(admin);
                oracle.removeFeed(victim);
                feedsBroken = true;
            }
        } else {
            bool cp = vaultC.paused();
            bool pp = vaultP.paused();
            if (cp) {
                vm.prank(guardian);
                vaultC.unpause();
            }
            if (pp) {
                vm.prank(guardian);
                vaultP.unpause();
            }
        }
    }

    function _fund(uint256 amt) internal {
        IMintLike(usdg).mint(admin, amt);
        IERC20(usdg).approve(address(desk), amt);
        desk.fundReserve(amt);
    }
}

interface TestTokenLike {
    function mint(address to, uint256 amount) external;
}
