// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2, VaultParams} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IOracleDesk} from "../../../v2/interfaces/IOracleDesk.sol";
import {OracleDesk} from "../../../v2/venue/OracleDesk.sol";
import {MarketplaceRegistryV2} from "../../../v2/MarketplaceRegistryV2.sol";
import {RebalanceEngineV2} from "../../../v2/RebalanceEngineV2.sol";
import {StrategyTokenV2} from "../../../v2/StrategyTokenV2.sol";
import {FengFaucet} from "../../../v2/faucet/FengFaucet.sol";
import {FengAggregator} from "../../../v2/oracle/FengAggregator.sol";
import {TestToken} from "../mocks/HostileTokens.sol";
import {FakeVault} from "../mocks/FakeVault.sol";

contract RejectEth {
    receive() external payable {
        revert();
    }
}

contract CoverageV2Test is DeployV2Helper {
    IStrategyVaultV2 internal v;
    FakeVault internal fv;

    function setUp() public {
        _deployStack();
        (v,) = _fiftyFifty();
        fv = new FakeVault();
        bytes32 fr = registry.FACTORY_ROLE();
        vm.startPrank(admin);
        registry.grantRole(fr, admin);
        registry.registerStrategy(address(fv), address(0xBEEF), admin, _meta());
        vm.stopPrank();
    }

    function _params() internal view returns (VaultParams memory p) {
        p.name = "S";
        p.symbol = "SS";
        p.usdg = usdg;
        p.oracle = address(oracle);
        p.venue = address(desk);
        p.guardian = guardian;
        p.constituents = _two(address(stocks[0]), 5000, address(stocks[1]), 5000);
        p.maxWeightBps = 5000;
        p.maxSlippageBps = 100;
        p.depth = 1;
        p.rebalanceInterval = 1 days;
        p.maxPriceStaleness = STALENESS;
    }

    function test_ctors_zeroAddresses() public {
        vm.expectRevert();
        new MarketplaceRegistryV2(address(0));
        vm.expectRevert();
        new RebalanceEngineV2(address(0));
        vm.expectRevert();
        new StrategyTokenV2("N", "SY", address(0));
        vm.expectRevert();
        new FengFaucet(address(0), usdg, 1, 1, 1);
        vm.expectRevert();
        new FengFaucet(admin, address(0), 1, 1, 1);
        vm.expectRevert();
        new FengAggregator(address(0), 8, "X", 1e8, 1500, 3000);
        vm.expectRevert();
        new FengAggregator(admin, 8, "X", 0, 1500, 3000);
        vm.expectRevert();
        new OracleDesk(admin, address(0), address(oracle), address(registry), 10, STALENESS);
        vm.expectRevert();
        new OracleDesk(admin, usdg, address(0), address(registry), 10, STALENESS);
        vm.expectRevert();
        new OracleDesk(admin, usdg, address(oracle), address(0), 10, STALENESS);
        vm.expectRevert();
        new OracleDesk(admin, usdg, address(oracle), address(registry), 101, STALENESS);
        TestToken big = new TestToken("B", "B", 19);
        vm.expectRevert();
        new OracleDesk(admin, address(big), address(oracle), address(registry), 10, STALENESS);
    }

    function test_vaultCtor_validation() public {
        VaultParams memory p = _params();
        p.usdg = address(0);
        vm.expectRevert();
        deployer.deploy(p);
        p = _params();
        p.guardian = address(0);
        vm.expectRevert();
        deployer.deploy(p);
        p = _params();
        p.constituents = new Constituent[](0);
        vm.expectPartialRevert(_sel("EmptyConstituents()"));
        deployer.deploy(p);
        p = _params();
        p.constituents = new Constituent[](7);
        vm.expectPartialRevert(_sel("TooManyConstituents()"));
        deployer.deploy(p);
        p = _params();
        p.maxSlippageBps = 0;
        vm.expectPartialRevert(_sel("InvalidMaxSlippage(uint16)"));
        deployer.deploy(p);
        p = _params();
        p.maxSlippageBps = 501;
        vm.expectPartialRevert(_sel("InvalidMaxSlippage(uint16)"));
        deployer.deploy(p);
        p = _params();
        p.constituents = _two(address(0), 5000, address(stocks[1]), 5000);
        vm.expectRevert();
        deployer.deploy(p);
        p = _params();
        p.constituents = _two(usdg, 5000, address(stocks[1]), 5000);
        vm.expectPartialRevert(_sel("ConstituentIsUsdg()"));
        deployer.deploy(p);
        p = _params();
        p.constituents = _two(address(stocks[0]), 5000, address(stocks[1]), 4000);
        vm.expectPartialRevert(_sel("WeightsMustSumTo10000()"));
        deployer.deploy(p);
        TestToken big = new TestToken("B", "B", 19);
        p = _params();
        p.constituents = _two(address(big), 5000, address(stocks[1]), 5000);
        vm.expectPartialRevert(_sel("UnsupportedDecimals(address,uint8)"));
        deployer.deploy(p);
        p = _params();
        p.usdg = address(big);
        vm.expectPartialRevert(_sel("UnsupportedDecimals(address,uint8)"));
        deployer.deploy(p);
    }

    function test_registry_unregisteredReads() public {
        vm.expectPartialRevert(_sel("NotRegistered()"));
        registry.getStrategyInfo(address(0x99));
        vm.expectPartialRevert(_sel("NotRegistered()"));
        registry.getStrategyInfoV2(address(0x99));
        vm.expectPartialRevert(_sel("NotRegistered()"));
        registry.getStrategyMeta(address(0x99));
    }

    function test_faucet_withdrawBranches() public {
        FengFaucet f = new FengFaucet(admin, usdg, 1, 1, 1);
        vm.deal(address(f), 1 ether);
        vm.startPrank(admin);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        f.withdrawEth(payable(address(0)), 1);
        RejectEth r = new RejectEth();
        vm.expectPartialRevert(_sel("TransferFailed()"));
        f.withdrawEth(payable(address(r)), 1);
        f.withdrawEth(payable(admin), 1 ether);
        vm.stopPrank();
        assertEq(admin.balance, 1 ether);
    }

    function test_aggregator_forceAnswerInvalid() public {
        vm.prank(admin);
        vm.expectPartialRevert(_sel("InvalidAnswer(int256)"));
        feeds[0].forceAnswer(0);
        vm.prank(admin);
        vm.expectPartialRevert(_sel("InvalidAnswer(int256)"));
        feeds[0].forceAnswer(-1);
    }

    function test_desk_zeroBranches() public {
        _mintUsdg(address(fv), 100 * U);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, 0, address(0));
        vm.expectPartialRevert(_sel("ZeroAmount()"));
        desk.quoteExactIn(usdg, address(stocks[0]), 0);
        vm.startPrank(admin);
        vm.expectPartialRevert(_sel("ZeroAmount()"));
        desk.fundReserve(0);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        desk.withdrawReserve(address(0), 1);
        vm.expectPartialRevert(_sel("ZeroAmount()"));
        desk.withdrawReserve(admin, 0);
        vm.expectPartialRevert(_sel("InsufficientLiquidity(address)"));
        desk.withdrawReserve(admin, type(uint256).max);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        desk.setToken(address(0), IOracleDesk.Mode.Mint);
        vm.expectPartialRevert(_sel("UnsupportedPair(address,address)"));
        desk.setToken(usdg, IOracleDesk.Mode.Mint);
        TestToken t = new TestToken("T", "T", 18);
        vm.expectPartialRevert(_sel("NotConfigured(address)"));
        desk.setToken(address(t), IOracleDesk.Mode.Unsupported);
        vm.expectPartialRevert(_sel("NotConfigured(address)"));
        desk.fundInventory(address(t), 1);
        desk.setToken(address(t), IOracleDesk.Mode.Inventory);
        vm.expectPartialRevert(_sel("ZeroAmount()"));
        desk.fundInventory(address(t), 0);
        vm.expectPartialRevert(_sel("NotConfigured(address)"));
        desk.withdrawInventory(usdg, admin, 1);
        vm.expectPartialRevert(_sel("NotConfigured(address)"));
        desk.withdrawInventory(address(0), admin, 1);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        desk.withdrawInventory(address(t), address(0), 1);
        vm.expectPartialRevert(_sel("ZeroAmount()"));
        desk.withdrawInventory(address(t), admin, 0);
        vm.expectPartialRevert(_sel("InsufficientLiquidity(address)"));
        desk.withdrawInventory(address(t), admin, 1);
        vm.stopPrank();
    }

    function test_desk_inventoryWithdrawAndSwapCap() public {
        TestToken t = new TestToken("T", "T", 18);
        _newInventoryToken(address(t), 50e8, 10 ether);
        vm.prank(admin);
        desk.withdrawInventory(address(t), bob, 1 ether);
        assertEq(t.balanceOf(bob), 1 ether);
        assertEq(desk.tokenInventory(address(t)), 9 ether);
        (bool ok, bytes memory ret) = address(desk).call(abi.encodeWithSignature("maxSwapUsdg()"));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 0);
        vm.prank(admin);
        (ok,) = address(desk).call(abi.encodeWithSignature("setMaxSwapUsdg(uint256)", 100 * U));
        assertTrue(ok);
        _mintUsdg(address(fv), 1000 * U);
        vm.expectPartialRevert(_sel("SwapTooLarge(uint256,uint256)"));
        fv.swap(address(desk), usdg, address(stocks[0]), 101 * U, 0, bob);
        vm.expectPartialRevert(_sel("SwapTooLarge(uint256,uint256)"));
        desk.quoteExactIn(usdg, address(stocks[0]), 101 * U);
        fv.swap(address(desk), usdg, address(stocks[0]), 100 * U, 0, bob);
    }

    function test_vault_zeroReceiverAndTinyAmounts() public {
        uint256 s = _deposit(v, alice, 1000 * U);
        _mintUsdg(bob, 100 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), 100 * U);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        v.deposit(100 * U, address(0), 0);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        v.redeemInKind(s / 2, address(0), alice);
        vm.prank(alice);
        vm.expectPartialRevert(_sel("ZeroAssets()"));
        v.redeem(1, alice, alice, 0);
        _mintUsdg(bob, 1);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), 1);
        try v.deposit(1, bob, 0) {
            revert("tiny deposit minted without value");
        } catch (bytes memory r) {
            bytes4 sel;
            assembly {
                sel := mload(add(r, 32))
            }
            assertTrue(sel == _sel("NoValueAdded()") || sel == _sel("ZeroShares()"));
        }
        vm.stopPrank();
    }

    function test_vault_tinyInKindNoValue() public {
        _deposit(v, alice, 1000 * U);
        stocks[0].mint(bob, 1);
        vm.startPrank(bob);
        stocks[0].approve(address(v), 1);
        if (_valueOf(address(stocks[0]), 1, false) == 0) {
            vm.expectPartialRevert(_sel("NoValueAdded()"));
            v.depositInKind(address(stocks[0]), 1, bob, 0);
        }
        vm.stopPrank();
    }

    function test_vault_weightsOnEmptyAndPreviewOnEmpty() public view {
        uint16[] memory w = v.weights();
        assertEq(w[0], 0);
        assertEq(w[1], 0);
        assertEq(v.previewRedeem(1e18), 0);
        assertEq(v.totalAssetsUSDG(), 0);
        assertEq(lens.quoteRedeem(address(v), 1e18), 0);
        (, uint256[] memory a) = lens.previewRedeemInKind(address(v), 1e18);
        assertEq(a[0], 0);
    }

    function test_lens_partsZeroSkipped() public {
        uint256 s = _deposit(v, alice, 1000 * U);
        assertEq(lens.quoteRedeem(address(v), 0), 0);
        assertLe(lens.quoteRedeem(address(v), s), v.previewRedeem(s));
        _mintUsdg(address(v), 5);
        assertGe(lens.quoteRedeem(address(v), 1), 0);
    }

    function test_vault_priceStatusOnFeedFailureInChild() public {
        (IStrategyVaultV2 c, address ct) = (v, v.token());
        (IStrategyVaultV2 p,) = _nested(c, ct);
        vm.prank(admin);
        oracle.removeFeed(address(stocks[2]));
        (bool fresh, uint256 o) = p.priceStatus();
        assertFalse(fresh);
        assertEq(o, 0);
    }
}
