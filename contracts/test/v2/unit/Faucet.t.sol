// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FengFaucet} from "../../../v2/faucet/FengFaucet.sol";
import {MockUSDGV2} from "../../../v2/mocks/MockUSDGV2.sol";
import {StrategyTokenV2} from "../../../v2/StrategyTokenV2.sol";

contract FaucetTest is Test {
    FengFaucet internal faucet;
    MockUSDGV2 internal usdg;
    address internal admin = makeAddr("admin");
    address internal dispenser = makeAddr("dispenser");
    address internal rnd = makeAddr("rnd");

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.startPrank(admin);
        usdg = new MockUSDGV2(admin, 6);
        faucet = new FengFaucet(admin, address(usdg), 0.0002 ether, 10_000e6, 2);
        usdg.grantRole(usdg.MINTER_ROLE(), address(faucet));
        faucet.grantRole(faucet.DISPENSER_ROLE(), dispenser);
        vm.stopPrank();
        vm.deal(address(faucet), 1 ether);
    }

    function test_claim_paysOnce() public {
        address u = makeAddr("u");
        vm.prank(dispenser);
        faucet.claimFor(u);
        assertEq(u.balance, 0.0002 ether);
        assertEq(usdg.balanceOf(u), 10_000e6);
        assertTrue(faucet.hasClaimed(u));
        assertEq(faucet.claimsToday(), 1);
        vm.prank(dispenser);
        vm.expectRevert(abi.encodeWithSignature("AlreadyClaimed(address)", u));
        faucet.claimFor(u);
    }

    function test_claim_event() public {
        address u = makeAddr("u");
        vm.expectEmit(true, true, false, true, address(faucet));
        emit Claimed(u, dispenser, 0.0002 ether, 10_000e6);
        vm.prank(dispenser);
        faucet.claimFor(u);
    }

    event Claimed(address indexed recipient, address indexed dispenser, uint256 ethAmount, uint256 usdgAmount);

    function test_dailyCapAndReset() public {
        vm.startPrank(dispenser);
        faucet.claimFor(makeAddr("a"));
        faucet.claimFor(makeAddr("b"));
        vm.expectRevert(abi.encodeWithSignature("DailyCapReached(uint256)", uint256(2)));
        faucet.claimFor(makeAddr("c"));
        vm.warp(block.timestamp + 1 days);
        faucet.claimFor(makeAddr("c"));
        vm.stopPrank();
        assertEq(faucet.claimsToday(), 1);
        assertEq(faucet.currentDay(), block.timestamp / 1 days);
    }

    function test_contractRecipientRejected() public {
        vm.prank(dispenser);
        vm.expectRevert(abi.encodeWithSignature("RecipientIsContract(address)", address(usdg)));
        faucet.claimFor(address(usdg));
    }

    function test_zeroRecipientRejected() public {
        vm.prank(dispenser);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        faucet.claimFor(address(0));
    }

    function test_dispenserOnly() public {
        vm.prank(rnd);
        vm.expectRevert();
        faucet.claimFor(rnd);
        vm.prank(admin);
        vm.expectRevert();
        faucet.claimFor(rnd);
    }

    function test_emptyFaucet() public {
        vm.prank(admin);
        faucet.withdrawEth(payable(admin), address(faucet).balance);
        vm.prank(dispenser);
        vm.expectRevert(abi.encodeWithSignature("FaucetEmpty()"));
        faucet.claimFor(makeAddr("u"));
    }

    function test_setParamsAndWithdrawAdminOnly() public {
        vm.prank(rnd);
        vm.expectRevert();
        faucet.setParams(1, 1, 1);
        vm.prank(rnd);
        vm.expectRevert();
        faucet.withdrawEth(payable(rnd), 1);
        vm.prank(admin);
        faucet.setParams(1 ether / 1000, 5e6, 10);
        assertEq(faucet.ethPerClaim(), 1 ether / 1000);
        assertEq(faucet.usdgPerClaim(), 5e6);
        assertEq(faucet.dailyCap(), 10);
    }

    function test_receiveEth() public {
        vm.deal(rnd, 1 ether);
        vm.prank(rnd);
        (bool ok,) = address(faucet).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(address(faucet).balance, 1.5 ether);
    }
}

contract MockUsdgAndTokenTest is Test {
    address internal admin = makeAddr("admin");
    address internal rnd = makeAddr("rnd");

    function test_mockUsdg_decimalsAndMinter() public {
        MockUSDGV2 a = new MockUSDGV2(admin, 6);
        MockUSDGV2 b = new MockUSDGV2(admin, 18);
        assertEq(a.decimals(), 6);
        assertEq(b.decimals(), 18);
        assertEq(a.symbol(), "USDG");
        assertEq(a.name(), "Mock Global Dollar");
        vm.prank(rnd);
        vm.expectRevert();
        a.mint(rnd, 1);
        vm.prank(admin);
        a.mint(rnd, 5);
        assertEq(a.balanceOf(rnd), 5);
    }

    function test_strategyToken_vaultOnly() public {
        StrategyTokenV2 t = new StrategyTokenV2("N", "SY", address(this));
        assertEq(t.decimals(), 18);
        assertEq(t.vault(), address(this));
        t.mint(rnd, 100);
        vm.startPrank(rnd);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        t.mint(rnd, 1);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        t.burn(rnd, 1);
        vm.expectRevert(abi.encodeWithSignature("NotVault()"));
        t.burnFrom(rnd, rnd, 1);
        vm.stopPrank();
        t.burn(rnd, 10);
        assertEq(t.balanceOf(rnd), 90);
    }

    function test_strategyToken_burnFromSpendsAllowance() public {
        StrategyTokenV2 t = new StrategyTokenV2("N", "SY", address(this));
        address spender = makeAddr("spender");
        t.mint(rnd, 100);
        vm.expectRevert();
        t.burnFrom(rnd, spender, 50);
        vm.prank(rnd);
        t.approve(spender, 60);
        t.burnFrom(rnd, spender, 50);
        assertEq(t.balanceOf(rnd), 50);
        assertEq(t.allowance(rnd, spender), 10);
    }
}
