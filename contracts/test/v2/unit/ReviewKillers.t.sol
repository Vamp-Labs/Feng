// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IStrategyFactoryV2} from "../../../v2/interfaces/IStrategyFactoryV2.sol";
import {StrategyFactoryV2} from "../../../v2/StrategyFactoryV2.sol";
import {IVenue} from "../../../v2/interfaces/IVenue.sol";
import {IOracleDesk} from "../../../v2/interfaces/IOracleDesk.sol";
import {TestToken} from "../mocks/HostileTokens.sol";
import {HostileVenue} from "../mocks/HostileVenues.sol";

contract OddFeed {
    uint8 public decimals;
    int256 public ans;
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

contract PartialPullVenue is IVenue {
    address public immutable override usdg;
    mapping(address => uint256) public tokensPerUsdgUnit;

    constructor(address usdg_) {
        usdg = usdg_;
    }

    function configure(address token, uint256 k) external {
        tokensPerUsdgUnit[token] = k;
    }

    function isSupported(address token) external view returns (bool) {
        return tokensPerUsdgUnit[token] != 0;
    }

    function quoteExactIn(address, address tokenOut, uint256 amountIn) public view returns (uint256) {
        return amountIn * tokensPerUsdgUnit[tokenOut];
    }

    function swapExactIn(address tokenIn, address tokenOut, uint256 amountIn, uint256, address recipient)
        external
        returns (uint256 out)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn / 2);
        out = quoteExactIn(tokenIn, tokenOut, amountIn);
        TestToken(tokenOut).mint(recipient, out);
    }
}

contract ReviewKillersTest is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function test_R04_parentCheckpointRevertsOnStaleChild() public {
        (IStrategyVaultV2 c, address ct) = _fiftyFifty();
        (IStrategyVaultV2 p,) = _nested(c, ct);
        _deposit(p, alice, 10_000 * U);
        vm.warp(block.timestamp + 13 hours);
        vm.prank(relayer);
        feeds[2].refresh();
        vm.expectRevert(abi.encodeWithSelector(IStrategyVaultV2.StalePrice.selector, ct, T0));
        p.checkpoint();
    }

    function test_R05_partialPullLeavesNoAllowance() public {
        PartialPullVenue pv = new PartialPullVenue(usdg);
        pv.configure(address(stocks[0]), 1e18 / (400 * U));
        pv.configure(address(stocks[1]), 1e18 / (250 * U));
        StrategyFactoryV2 f2 = new StrategyFactoryV2(
            address(registry), address(oracle), address(pv), usdg, guardian, address(deployer), STALENESS
        );
        bytes32 fr = registry.FACTORY_ROLE();
        vm.prank(admin);
        registry.grantRole(fr, address(f2));
        (IStrategyVaultV2 v,) = _createWith(
            IStrategyFactoryV2(address(f2)),
            "PP",
            _two(address(stocks[0]), 5000, address(stocks[1]), 5000),
            5000,
            7 days,
            100
        );
        _deposit(v, alice, 1000 * U);
        assertEq(IERC20(usdg).allowance(address(v), address(pv)), 0);
    }

    function test_R06_deskBuyPriceRoundsUpWithOddPrice() public {
        OddFeed bf = new OddFeed();
        vm.startPrank(admin);
        TestToken t = new TestToken("ODD", "ODD", 18);
        oracle.setFeed(address(t), address(bf));
        desk.setToken(address(t), IOracleDesk.Mode.Mint);
        vm.stopPrank();
        bf.set(18, int256(100e18 + 1), block.timestamp);
        uint256 amt = 1_000_000 * U;
        uint256 p = 100e18 + 1;
        uint256 priceCeil = Math.mulDiv(p, BPS + SPREAD, BPS, Math.Rounding.Ceil);
        uint256 priceFloor = Math.mulDiv(p, BPS + SPREAD, BPS, Math.Rounding.Floor);
        assertEq(priceCeil, priceFloor + 1);
        uint256 unit = 10 ** (18 + 18 - usdgDec);
        assertEq(desk.quoteExactIn(usdg, address(t), amt), Math.mulDiv(amt, unit, priceCeil));
        assertLt(Math.mulDiv(amt, unit, priceCeil), Math.mulDiv(amt, unit, priceFloor));
    }

    function test_R06_deskSellPriceRoundsDownWithOddPrice() public {
        OddFeed bf = new OddFeed();
        vm.startPrank(admin);
        TestToken t = new TestToken("ODD", "ODD", 18);
        oracle.setFeed(address(t), address(bf));
        desk.setToken(address(t), IOracleDesk.Mode.Mint);
        vm.stopPrank();
        uint256 p = 100e18 + 1;
        bf.set(18, int256(p), block.timestamp);
        uint256 amt = 1e30;
        uint256 priceFloor = Math.mulDiv(p, BPS - SPREAD, BPS, Math.Rounding.Floor);
        uint256 priceCeil = Math.mulDiv(p, BPS - SPREAD, BPS, Math.Rounding.Ceil);
        assertEq(priceCeil, priceFloor + 1);
        uint256 unit = 10 ** (18 + 18 - usdgDec);
        uint256 q = desk.quoteExactIn(address(t), usdg, amt);
        assertEq(q, Math.mulDiv(amt, priceFloor, unit));
        assertLt(q, Math.mulDiv(amt, priceCeil, unit));
    }

    function test_R08_redeemIdleSliceRoundsDown() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 amt = 19 * U / 1000;
        uint256 S = _deposit(v, alice, amt);
        uint256 idle = IERC20(usdg).balanceOf(address(v));
        assertEq(idle, amt);
        uint256 sh = S / 3;
        vm.prank(alice);
        uint256 out = v.redeem(sh, alice, alice, 0);
        assertEq(out, Math.mulDiv(idle, sh, S));
        assertLt(out, Math.mulDiv(idle, sh, S, Math.Rounding.Ceil));
    }

    function testFuzz_R08_redeemIdleSliceFloorExact(uint256 amtSeed, uint256 shSeed) public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 amt = bound(amtSeed, U / 1000, (U / 50) - 1);
        uint256 S = _deposit(v, alice, amt);
        uint256 idle = IERC20(usdg).balanceOf(address(v));
        assertEq(idle, amt);
        uint256 sh = bound(shSeed, 1, S);
        uint256 expected = Math.mulDiv(idle, sh, S);
        vm.prank(alice);
        if (expected == 0) vm.expectRevert();
        uint256 out = v.redeem(sh, alice, alice, 0);
        if (expected != 0) assertEq(out, expected);
    }
}

contract ReviewKillersVenueTest is DeployV2Helper {
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

    function test_R07_redeemSellLegShortDeliveryRevertsSlippage() public {
        uint256 s = _deposit(v, alice, 1000 * U);
        hv.setShortBps(500);
        vm.prank(alice);
        vm.expectPartialRevert(_sel("SlippageExceeded(uint256,uint256)"));
        v.redeem(s / 2, alice, alice, 0);
        assertEq(_shareToken(v).balanceOf(alice), s);
    }

    function test_R07_redeemSellLegShortWithinToleranceStillPays() public {
        uint256 s = _deposit(v, alice, 1000 * U);
        hv.setShortBps(50);
        vm.prank(alice);
        uint256 out = v.redeem(s / 2, alice, alice, 0);
        assertGt(out, 0);
        assertLt(out, 500 * U);
    }
}
