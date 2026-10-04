// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DeployV2Helper} from "../v2/helpers/DeployV2Helper.sol";
import {IStrategyVaultV2} from "../../v2/interfaces/IStrategyVaultV2.sol";
import {IStrategyFactoryV2} from "../../v2/interfaces/IStrategyFactoryV2.sol";
import {StrategyFactoryV2} from "../../v2/StrategyFactoryV2.sol";
import {IVenue} from "../../v2/interfaces/IVenue.sol";
import {IOracleDesk} from "../../v2/interfaces/IOracleDesk.sol";
import {TestToken} from "../v2/mocks/HostileTokens.sol";
import {BadFeed} from "./Review.t.sol";

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

contract Killers is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function test_K1_parentCheckpointRevertsOnStaleChild() public {
        (IStrategyVaultV2 c, address ct) = _fiftyFifty();
        (IStrategyVaultV2 p,) = _nested(c, ct);
        _deposit(p, alice, 10_000 * U);
        vm.warp(block.timestamp + 13 hours);
        vm.prank(relayer);
        feeds[2].refresh();
        vm.expectRevert(abi.encodeWithSelector(IStrategyVaultV2.StalePrice.selector, ct, T0));
        p.checkpoint();
    }

    function test_K2_partialPullLeavesNoAllowance() public {
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

    function test_K4_redeemIdleSliceRoundsDown() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 amt = 19 * U / 1000;
        uint256 S = _deposit(v, alice, amt);
        uint256 idle = IERC20(usdg).balanceOf(address(v));
        assertEq(idle, amt);
        uint256 sh = S / 3;
        vm.prank(alice);
        uint256 out = v.redeem(sh, alice, alice, 0);
        assertEq(out, Math.mulDiv(idle, sh, S));
    }

    function test_K3_deskBuyPriceRoundsUpWithOddPrice() public {
        BadFeed bf = new BadFeed();
        vm.startPrank(admin);
        TestToken t = new TestToken("ODD", "ODD", 18);
        oracle.setFeed(address(t), address(bf));
        desk.setToken(address(t), IOracleDesk.Mode.Mint);
        vm.stopPrank();
        bf.set(18, int256(100e18 + 1), block.timestamp);
        uint256 amt = 1_000_000 * U;
        uint256 p = 100e18 + 1;
        uint256 priceCeil = Math.mulDiv(p, BPS + SPREAD, BPS, Math.Rounding.Ceil);
        uint256 unit = 10 ** (18 + 18 - usdgDec);
        assertEq(desk.quoteExactIn(usdg, address(t), amt), Math.mulDiv(amt, unit, priceCeil));
    }
}

contract DustWindow is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function test_dustRedeemZeroAmountWindow() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 S = _deposit(v, alice, 10_000 * U);
        uint256 B = stocks[0].balanceOf(address(v));
        uint256 hits;
        uint256 shares = S * 2_500_000_000 / B;
        for (uint256 i = 0; i < 40; i++) {
            uint256 s = shares + i;
            vm.prank(alice);
            try v.redeem(s, alice, alice, 0) {} catch (bytes memory r) {
                bytes4 sel;
                assembly {
                    sel := mload(add(r, 32))
                }
                if (sel == IStrategyVaultV2.ZeroAmount.selector) hits++;
            }
        }
        emit log_named_uint("redeems reverting ZeroAmount among 40 consecutive dust sizes", hits);
    }
}
