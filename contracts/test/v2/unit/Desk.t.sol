// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {IOracleDesk} from "../../../v2/interfaces/IOracleDesk.sol";
import {IMarketplaceRegistryV2, StrategyMeta} from "../../../v2/interfaces/IMarketplaceRegistryV2.sol";
import {FakeVault} from "../mocks/FakeVault.sol";
import {TestToken, FeeOnTransferToken} from "../mocks/HostileTokens.sol";

abstract contract DeskBase is DeployV2Helper {
    FakeVault internal fv;

    function setUp() public virtual {
        _deployStack();
        fv = new FakeVault();
        vm.startPrank(admin);
        registry.grantRole(registry.FACTORY_ROLE(), admin);
        registry.registerStrategy(address(fv), address(0xBEEF), admin, _meta());
        vm.stopPrank();
    }

    function _k(address t) internal view returns (uint256) {
        return 10 ** (uint256(TestToken(t).decimals()) + 18 - usdgDec);
    }

    function _priceBuy(uint256 p) internal pure returns (uint256) {
        return (p * 10_010 + 9999) / 10_000;
    }

    function _priceSell(uint256 p) internal pure returns (uint256) {
        return p * 9990 / 10_000;
    }

    function test_buy_roundsAgainstBuyer() public {
        _setPrice(0, 412_34567891);
        address t = address(stocks[0]);
        uint256 p = _price18(t);
        uint256 amt = 777 * U + 13;
        _mintUsdg(address(fv), amt);
        uint256 q = desk.quoteExactIn(usdg, t, amt);
        vm.prank(address(fv));
        uint256 out = fv.swap(address(desk), usdg, t, amt, 0, bob);
        assertEq(out, amt * _k(t) / _priceBuy(p));
        assertEq(out, q);
        assertEq(IERC20(t).balanceOf(bob), out);
        assertEq(IERC20(t).balanceOf(address(desk)), 0);
    }

    function test_sell_roundsAgainstSeller() public {
        _setPrice(0, 412_34567891);
        address t = address(stocks[0]);
        uint256 p = _price18(t);
        uint256 amt = 3 * (10 ** TestToken(t).decimals()) + 17;
        stocks[0].mint(address(fv), amt);
        uint256 q = desk.quoteExactIn(t, usdg, amt);
        uint256 supply = IERC20(t).totalSupply();
        uint256 reserve = IERC20(usdg).balanceOf(address(desk));
        fv.swap(address(desk), t, usdg, amt, 0, bob);
        uint256 expected = amt * _priceSell(p) / _k(t);
        assertEq(IERC20(usdg).balanceOf(bob), expected);
        assertEq(q, expected);
        assertEq(IERC20(t).totalSupply(), supply - amt);
        assertEq(IERC20(usdg).balanceOf(address(desk)), reserve - expected);
    }

    function test_swap_onlyRegisteredVault() public {
        _mintUsdg(attacker, 100 * U);
        vm.startPrank(attacker);
        IERC20(usdg).approve(address(desk), 100 * U);
        vm.expectPartialRevert(_sel("NotVault(address)"));
        desk.swapExactIn(usdg, address(stocks[0]), 100 * U, 0, attacker);
        vm.stopPrank();
        assertGt(desk.quoteExactIn(usdg, address(stocks[0]), 100 * U), 0);
    }

    function test_swap_staleReverts() public {
        _mintUsdg(address(fv), 100 * U);
        vm.warp(block.timestamp + STALENESS + 1);
        vm.expectPartialRevert(_sel("StalePrice(address,uint256)"));
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, 0, bob);
    }

    function test_swap_staleBoundaryInclusive() public {
        _mintUsdg(address(fv), 100 * U);
        vm.warp(block.timestamp + STALENESS);
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, 0, bob);
    }

    function test_swap_unsupportedPairs() public {
        _mintUsdg(address(fv), 100 * U);
        stocks[0].mint(address(fv), 1e6);
        vm.expectPartialRevert(_sel("UnsupportedPair(address,address)"));
        fv.swap(address(desk), usdg, usdg, 100 * U, 0, bob);
        vm.expectPartialRevert(_sel("UnsupportedPair(address,address)"));
        fv.swap(address(desk), address(stocks[0]), address(stocks[1]), 1e6, 0, bob);
        assertFalse(desk.isSupported(usdg));
        assertTrue(desk.isSupported(address(stocks[0])));
    }

    function test_swap_unsupportedModeStopsSwaps() public {
        _mintUsdg(address(fv), 100 * U);
        vm.prank(admin);
        desk.setToken(address(stocks[0]), IOracleDesk.Mode.Unsupported);
        assertFalse(desk.isSupported(address(stocks[0])));
        vm.expectRevert();
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, 0, bob);
    }

    function test_swap_zeroAmount() public {
        vm.expectPartialRevert(_sel("ZeroAmount()"));
        fv.swap(address(desk), usdg, address(stocks[0]), 0, 0, bob);
        vm.prank(admin);
        feeds[0].forceAnswer(1);
        stocks[0].mint(address(fv), 1);
        if (_k(address(stocks[0])) <= _priceSell(_price18(address(stocks[0])))) return;
        vm.expectPartialRevert(_sel("ZeroAmount()"));
        fv.swap(address(desk), address(stocks[0]), usdg, 1, 0, bob);
    }

    function test_swap_minAmountOutEnforced() public {
        _mintUsdg(address(fv), 100 * U);
        uint256 q = desk.quoteExactIn(usdg, address(stocks[0]), 100 * U);
        vm.expectPartialRevert(_sel("VenueSlippage(uint256,uint256)"));
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, q + 1, bob);
        _mintUsdg(address(fv), 0);
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, q, bob);
    }

    function test_swap_emitsSwapped() public {
        _mintUsdg(address(fv), 100 * U);
        uint256 q = desk.quoteExactIn(usdg, address(stocks[0]), 100 * U);
        vm.expectEmit(true, true, true, true, address(desk));
        emit Swapped(address(fv), usdg, address(stocks[0]), 100 * U, q, bob);
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, 0, bob);
    }

    event Swapped(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    function test_reserveIdentity_acrossActions() public {
        address t = address(stocks[0]);
        _mintUsdg(address(fv), 5000 * U);
        fv.swap(address(desk), usdg, t, 5000 * U, 0, address(fv));
        uint256 bal = IERC20(t).balanceOf(address(fv));
        fv.swap(address(desk), t, usdg, bal / 2, 0, address(fv));
        vm.prank(admin);
        desk.withdrawReserve(admin, 1234 * U);
        (uint256 funded, uint256 withdrawn, uint256 buyIn, uint256 sellOut) = desk.accounting();
        assertEq(funded, 10_000_000 * U);
        assertEq(withdrawn, 1234 * U);
        assertEq(buyIn, 5000 * U);
        assertGt(sellOut, 0);
        assertEq(IERC20(usdg).balanceOf(address(desk)), funded + buyIn - sellOut - withdrawn);
        assertEq(desk.reserveUsdg(), IERC20(usdg).balanceOf(address(desk)));
        _mintUsdg(address(desk), 5);
        assertEq(IERC20(usdg).balanceOf(address(desk)), funded + buyIn - sellOut - withdrawn + 5);
    }

    function test_sell_reserveShortfallReverts() public {
        address t = address(stocks[0]);
        uint256 one = 10 ** TestToken(t).decimals();
        stocks[0].mint(address(fv), one);
        uint256 r = desk.reserveUsdg();
        vm.prank(admin);
        desk.withdrawReserve(admin, r);
        vm.expectPartialRevert(_sel("InsufficientLiquidity(address)"));
        fv.swap(address(desk), t, usdg, one, 0, bob);
    }

    function test_inventoryMode_buySell() public {
        TestToken inv = new TestToken("INV", "INV", 18);
        _newInventoryToken(address(inv), 50e8, 1000 ether);
        assertEq(desk.tokenInventory(address(inv)), 1000 ether);
        _mintUsdg(address(fv), 500 * U);
        uint256 out = fv.swap(address(desk), usdg, address(inv), 500 * U, 0, address(fv));
        assertEq(inv.balanceOf(address(fv)), out);
        assertEq(desk.tokenInventory(address(inv)), 1000 ether - out);
        fv.swap(address(desk), address(inv), usdg, out, 0, address(fv));
        assertEq(desk.tokenInventory(address(inv)), 1000 ether);
        assertEq(inv.totalSupply(), 1000 ether + 0);
    }

    function test_inventoryMode_shortfallReverts() public {
        TestToken inv = new TestToken("INV", "INV", 18);
        _newInventoryToken(address(inv), 50e8, 1 ether);
        _mintUsdg(address(fv), 5000 * U);
        vm.expectPartialRevert(_sel("InsufficientLiquidity(address)"));
        fv.swap(address(desk), usdg, address(inv), 5000 * U, 0, address(fv));
    }

    function test_inventoryMode_feeOnTransferSellPricedOnReceived() public {
        FeeOnTransferToken inv = new FeeOnTransferToken("FOT", "FOT", 18);
        _newInventoryToken(address(inv), 50e8, 1000 ether);
        inv.setFeeBps(100);
        inv.mint(address(fv), 100 ether);
        uint256 p = _price18(address(inv));
        uint256 expected = 99 ether * _priceSell(p) / _k(address(inv));
        fv.swap(address(desk), address(inv), usdg, 100 ether, 0, bob);
        assertEq(IERC20(usdg).balanceOf(bob), expected);
    }

    function test_admin_onlyOwner() public {
        vm.startPrank(attacker);
        vm.expectRevert();
        desk.setToken(address(stocks[0]), IOracleDesk.Mode.Unsupported);
        vm.expectRevert();
        desk.setSpreadBps(5);
        vm.expectRevert();
        desk.withdrawReserve(attacker, 1);
        vm.expectRevert();
        desk.withdrawInventory(address(stocks[0]), attacker, 1);
        vm.stopPrank();
    }

    function test_setSpreadBps_capAndEffect() public {
        vm.startPrank(admin);
        vm.expectPartialRevert(_sel("SpreadTooHigh(uint16)"));
        desk.setSpreadBps(101);
        desk.setSpreadBps(100);
        vm.stopPrank();
        assertEq(desk.spreadBps(), 100);
        uint256 p = _price18(address(stocks[0]));
        uint256 expected = 100 * U * _k(address(stocks[0])) / ((p * 10_100 + 9999) / 10_000);
        assertEq(desk.quoteExactIn(usdg, address(stocks[0]), 100 * U), expected);
    }

    function test_setToken_decimalsTooHigh() public {
        TestToken big = new TestToken("BIG", "BIG", 19);
        vm.prank(admin);
        vm.expectPartialRevert(_sel("DecimalsTooHigh(address,uint8)"));
        desk.setToken(address(big), IOracleDesk.Mode.Inventory);
        assertEq(desk.tokenDecimals(address(stocks[0])), _stockDecimals());
        assertEq(uint8(desk.mode(address(stocks[0]))), uint8(IOracleDesk.Mode.Mint));
    }

    function test_views() public view {
        assertEq(desk.owner(), admin);
        assertEq(desk.oracle(), address(oracle));
        assertEq(desk.registry(), address(registry));
        assertEq(desk.maxPriceStaleness(), STALENESS);
        assertEq(desk.spreadBps(), SPREAD);
        assertEq(desk.usdg(), usdg);
    }
}

contract Desk_U6_S18 is DeskBase {}

contract Desk_U18_S18 is DeskBase {
    constructor() {
        cfgUsdg = 18;
    }
}

contract Desk_U6_S8 is DeskBase {
    constructor() {
        cfgStock = 8;
    }
}

contract Desk_U18_S8 is DeskBase {
    constructor() {
        cfgUsdg = 18;
        cfgStock = 8;
    }
}
