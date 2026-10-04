// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {IStrategyVaultV2} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IRebalanceEngineV2} from "../../../v2/interfaces/IRebalanceEngineV2.sol";
import {IMarketplaceRegistryV2} from "../../../v2/interfaces/IMarketplaceRegistryV2.sol";
import {RebalanceEngineV2} from "../../../v2/RebalanceEngineV2.sol";
import {MarketplaceRegistryV2} from "../../../v2/MarketplaceRegistryV2.sol";
import {OracleDesk} from "../../../v2/venue/OracleDesk.sol";
import {FengFaucet} from "../../../v2/faucet/FengFaucet.sol";
import {FengAggregator} from "../../../v2/oracle/FengAggregator.sol";
import {MockUSDGV2} from "../../../v2/mocks/MockUSDGV2.sol";
import {FakeVault} from "../mocks/FakeVault.sol";
import {DeployV2} from "../../../../script/DeployV2.s.sol";

contract FlagsFollowupTest is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function test_R09_dustVaultNeverReportsThresholdBased() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        _deposit(v, alice, 2 * U);
        _setPrice(0, 404e8);
        (bool tb, bool th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
        vm.expectRevert(IStrategyVaultV2.RebalanceNotNeeded.selector);
        v.executeRebalance();
    }

    function test_R09_dustVaultTimeBasedStillRebalancesAndStaysClear() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        _deposit(v, alice, 2 * U);
        vm.warp(block.timestamp + 7 days);
        _refreshAll();
        _setPrice(0, 404e8);
        (bool tb, bool th) = v.rebalanceNeeded();
        assertTrue(tb);
        assertFalse(th);
        v.executeRebalance();
        (tb, th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
    }

    function test_R09_largeVaultStillFlagsAndRebalanceClearsFlag() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        _deposit(v, alice, 10_000 * U);
        _setPrice(0, 440e8);
        (bool tb, bool th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertTrue(th);
        v.executeRebalance();
        (tb, th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
    }

    function testFuzz_R09_thresholdFlagAlwaysClearsAfterRebalance(uint256 amtSeed, uint256 pxSeed, bool tsla) public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 amt = bound(amtSeed, U / 10, 100_000 * U);
        _deposit(v, alice, amt);
        int256 px = int256(bound(pxSeed, tsla ? 340e8 : 213e8, tsla ? 460e8 : 287e8));
        _setPrice(tsla ? 0 : 1, px);
        (, bool th) = v.rebalanceNeeded();
        if (!th) return;
        v.executeRebalance();
        (, th) = v.rebalanceNeeded();
        assertFalse(th);
    }

    function test_R10_emptyVaultWithDonationIsNeverNeeded() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        stocks[0].mint(address(v), 1e18);
        (bool tb, bool th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
        vm.expectRevert(IStrategyVaultV2.RebalanceNotNeeded.selector);
        v.executeRebalance();
    }

    function test_R10_emptyVaultWithDonationNeverNeededAfterInterval() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        stocks[0].mint(address(v), 1e18);
        vm.warp(block.timestamp + 30 days);
        _refreshAll();
        (bool tb, bool th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
        vm.expectRevert(IStrategyVaultV2.RebalanceNotNeeded.selector);
        v.executeRebalance();
    }

    function test_R10_fullyRedeemedVaultWithDonationNeverNeeded() public {
        (IStrategyVaultV2 v,) = _fiftyFifty();
        uint256 s = _deposit(v, alice, 1000 * U);
        vm.prank(alice);
        v.redeemInKind(s, alice, alice);
        stocks[0].mint(address(v), 5e18);
        (bool tb, bool th) = v.rebalanceNeeded();
        assertFalse(tb);
        assertFalse(th);
    }
}

contract ZeroAddressFollowupTest is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function test_engine_zeroRegistryReverts() public {
        vm.expectRevert(IRebalanceEngineV2.ZeroAddress.selector);
        new RebalanceEngineV2(address(0));
    }

    function test_registry_zeroAdminReverts() public {
        vm.expectRevert(IMarketplaceRegistryV2.ZeroAddress.selector);
        new MarketplaceRegistryV2(address(0));
    }

    function test_engineAndRegistry_validConstructorsStillWork() public {
        RebalanceEngineV2 e = new RebalanceEngineV2(address(registry));
        assertEq(e.registry(), address(registry));
        MarketplaceRegistryV2 r = new MarketplaceRegistryV2(admin);
        assertTrue(r.hasRole(r.DEFAULT_ADMIN_ROLE(), admin));
    }
}

contract DeskCapTest is DeployV2Helper {
    event MaxSwapSet(uint256 maxSwapUsdg);

    FakeVault internal fv;

    function setUp() public {
        _deployStack();
        fv = new FakeVault();
        vm.startPrank(admin);
        registry.grantRole(registry.FACTORY_ROLE(), admin);
        registry.registerStrategy(address(fv), address(0xBEEF), admin, _meta());
        vm.stopPrank();
    }

    function _swapBuy(uint256 amt) internal returns (uint256) {
        _mintUsdg(address(fv), amt);
        return fv.swap(address(desk), usdg, address(stocks[0]), amt, 0, bob);
    }

    function _swapSell(uint256 tokenAmt) internal returns (uint256) {
        stocks[0].mint(address(fv), tokenAmt);
        return fv.swap(address(desk), address(stocks[0]), usdg, tokenAmt, 0, bob);
    }

    function test_cap_defaultIsZeroUnlimited() public {
        assertEq(desk.maxSwapUsdg(), 0);
        assertGt(_swapBuy(1_000_000 * U), 0);
        assertGt(desk.quoteExactIn(usdg, address(stocks[0]), 5_000_000 * U), 0);
    }

    function test_cap_ownerOnlySetter() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", attacker));
        desk.setMaxSwapUsdg(1);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", guardian));
        desk.setMaxSwapUsdg(1);
        assertEq(desk.maxSwapUsdg(), 0);
    }

    function test_cap_setEmitsAndStores() public {
        vm.expectEmit(false, false, false, true, address(desk));
        emit MaxSwapSet(5000 * U);
        vm.prank(admin);
        desk.setMaxSwapUsdg(5000 * U);
        assertEq(desk.maxSwapUsdg(), 5000 * U);
    }

    function test_cap_buySwapAboveCapRevertsAtCapPasses() public {
        vm.prank(admin);
        desk.setMaxSwapUsdg(5000 * U);
        _mintUsdg(address(fv), 5000 * U + 1);
        vm.expectRevert(abi.encodeWithSignature("SwapTooLarge(uint256,uint256)", 5000 * U + 1, 5000 * U));
        fv.swap(address(desk), usdg, address(stocks[0]), 5000 * U + 1, 0, bob);
        assertGt(fv.swap(address(desk), usdg, address(stocks[0]), 5000 * U, 0, bob), 0);
    }

    function test_cap_quoteAboveCapReverts() public {
        vm.prank(admin);
        desk.setMaxSwapUsdg(5000 * U);
        vm.expectRevert(abi.encodeWithSignature("SwapTooLarge(uint256,uint256)", 5000 * U + 1, 5000 * U));
        desk.quoteExactIn(usdg, address(stocks[0]), 5000 * U + 1);
        assertGt(desk.quoteExactIn(usdg, address(stocks[0]), 5000 * U), 0);
    }

    function test_cap_sellSideMeasuresUsdgOutput() public {
        vm.prank(admin);
        desk.setMaxSwapUsdg(1000 * U);
        uint256 perTokenUsdg = _price18(address(stocks[0]));
        uint256 tokensFor1100 = (1100 * U * 1e30) / perTokenUsdg;
        stocks[0].mint(address(fv), tokensFor1100);
        vm.expectPartialRevert(_sel("SwapTooLarge(uint256,uint256)"));
        fv.swap(address(desk), address(stocks[0]), usdg, tokensFor1100, 0, bob);
        vm.expectPartialRevert(_sel("SwapTooLarge(uint256,uint256)"));
        desk.quoteExactIn(address(stocks[0]), usdg, tokensFor1100);
        uint256 small = tokensFor1100 / 2;
        assertGt(desk.quoteExactIn(address(stocks[0]), usdg, small), 0);
        assertGt(fv.swap(address(desk), address(stocks[0]), usdg, small, 0, bob), 0);
    }

    function test_cap_zeroRestoresUnlimited() public {
        vm.startPrank(admin);
        desk.setMaxSwapUsdg(100 * U);
        vm.stopPrank();
        vm.expectPartialRevert(_sel("SwapTooLarge(uint256,uint256)"));
        desk.quoteExactIn(usdg, address(stocks[0]), 101 * U);
        vm.prank(admin);
        desk.setMaxSwapUsdg(0);
        assertGt(desk.quoteExactIn(usdg, address(stocks[0]), 1_000_000 * U), 0);
        assertGt(_swapBuy(1_000_000 * U), 0);
    }

    function test_cap_failedSwapLeavesNoState() public {
        vm.prank(admin);
        desk.setMaxSwapUsdg(100 * U);
        (uint256 f0, uint256 w0, uint256 b0, uint256 s0) = desk.accounting();
        _mintUsdg(address(fv), 200 * U);
        vm.expectPartialRevert(_sel("SwapTooLarge(uint256,uint256)"));
        fv.swap(address(desk), usdg, address(stocks[0]), 200 * U, 0, bob);
        (uint256 f1, uint256 w1, uint256 b1, uint256 s1) = desk.accounting();
        assertEq(f0, f1);
        assertEq(w0, w1);
        assertEq(b0, b1);
        assertEq(s0, s1);
        assertEq(IERC20(usdg).balanceOf(address(fv)), 200 * U);
    }

    function testFuzz_cap_buyBoundary(uint256 capSeed, uint256 amtSeed) public {
        uint256 cap = bound(capSeed, 1 * U, 1_000_000 * U);
        uint256 amt = bound(amtSeed, 1 * U, 2_000_000 * U);
        vm.prank(admin);
        desk.setMaxSwapUsdg(cap);
        if (amt > cap) vm.expectRevert(abi.encodeWithSignature("SwapTooLarge(uint256,uint256)", amt, cap));
        desk.quoteExactIn(usdg, address(stocks[0]), amt);
    }
}

contract FaucetDefaultsTest is Test {
    FengFaucet internal faucet;
    MockUSDGV2 internal usdg;
    address internal admin = makeAddr("admin");
    address internal dispenser = makeAddr("dispenser");

    uint256 internal constant ETH_PER_CLAIM = 0.0001 ether;
    uint256 internal constant DAILY_CAP = 40;

    function _deploy(uint256 fundWei) internal {
        vm.warp(1_700_000_000);
        vm.startPrank(admin);
        usdg = new MockUSDGV2(admin, 6);
        faucet = new FengFaucet(admin, address(usdg), ETH_PER_CLAIM, 10_000e6, DAILY_CAP);
        usdg.grantRole(usdg.MINTER_ROLE(), address(faucet));
        faucet.grantRole(faucet.DISPENSER_ROLE(), dispenser);
        vm.stopPrank();
        vm.deal(address(faucet), fundWei);
    }

    function test_defaults_claimPaysOneTenThousandthEth() public {
        _deploy(0.004 ether);
        assertEq(faucet.ethPerClaim(), 0.0001 ether);
        assertEq(faucet.dailyCap(), 40);
        address u = makeAddr("u");
        vm.prank(dispenser);
        faucet.claimFor(u);
        assertEq(u.balance, 0.0001 ether);
        assertEq(usdg.balanceOf(u), 10_000e6);
        assertEq(address(faucet).balance, 0.004 ether - 0.0001 ether);
    }

    function test_defaults_claim41RevertsDailyCapWhenFunded() public {
        _deploy(1 ether);
        vm.startPrank(dispenser);
        for (uint256 i = 0; i < 40; i++) {
            faucet.claimFor(address(uint160(0x1000 + i)));
        }
        assertEq(faucet.claimsToday(), 40);
        vm.expectRevert(abi.encodeWithSignature("DailyCapReached(uint256)", uint256(40)));
        faucet.claimFor(address(uint160(0x2000)));
        vm.stopPrank();
    }

    function test_defaults_exactFundingPaysExactlyFortyClaims() public {
        _deploy(0.004 ether);
        vm.startPrank(dispenser);
        for (uint256 i = 0; i < 40; i++) {
            faucet.claimFor(address(uint160(0x1000 + i)));
        }
        vm.stopPrank();
        assertEq(address(faucet).balance, 0);
        vm.prank(dispenser);
        vm.expectRevert(abi.encodeWithSignature("DailyCapReached(uint256)", uint256(40)));
        faucet.claimFor(address(uint160(0x2000)));
    }

    function test_defaults_cap40ResetsNextDay() public {
        _deploy(1 ether);
        vm.startPrank(dispenser);
        for (uint256 i = 0; i < 40; i++) {
            faucet.claimFor(address(uint160(0x1000 + i)));
        }
        vm.warp(block.timestamp + 1 days);
        faucet.claimFor(address(uint160(0x2000)));
        vm.stopPrank();
        assertEq(faucet.claimsToday(), 1);
    }

    function test_oldDefaultFundingWouldHaveStoppedAtTwenty() public {
        _deploy(0.004 ether);
        vm.prank(admin);
        faucet.setParams(0.0002 ether, 10_000e6, 40);
        vm.startPrank(dispenser);
        for (uint256 i = 0; i < 20; i++) {
            faucet.claimFor(address(uint160(0x1000 + i)));
        }
        vm.expectRevert(abi.encodeWithSignature("FaucetEmpty()"));
        faucet.claimFor(address(uint160(0x2000)));
        vm.stopPrank();
    }
}

contract DeployV2Harness is DeployV2 {
    function load(address deployer_) external {
        _loadConfig(deployer_);
    }

    function deployAll() external {
        _deploy();
    }

    function cfgRelayer() external view returns (address) {
        return cfg.relayer;
    }

    function cfgDispenser() external view returns (address) {
        return cfg.dispenser;
    }

    function cfgGuardian() external view returns (address) {
        return cfg.guardian;
    }

    function cfgFund() external view returns (uint256) {
        return cfg.faucetFundWei;
    }

    function cfgCap() external view returns (uint256) {
        return cfg.faucetDailyCap;
    }

    function cfgMaxSwap() external view returns (uint256) {
        return cfg.sandboxMaxSwap;
    }

    function addrs() external view returns (address desk, address faucet, address[5] memory feeds, address usdg) {
        return (d.desk, d.faucet, d.feeds, d.usdg);
    }
}

contract DeployV2GuardsTest is Test {
    address internal constant ZERO = address(0);
    address internal deployerAddr = makeAddr("deployerAddr");
    address internal relayerAddr = makeAddr("relayerAddr");
    address internal faucetAddr = makeAddr("faucetAddr");
    address internal guardianAddr = makeAddr("guardianAddr");

    function _env(string memory net, address relayer, address faucet, address legacy, address guard) internal {
        vm.setEnv("DEPLOY_NETWORK", net);
        vm.setEnv("RELAYER_ADDRESS", vm.toString(relayer));
        vm.setEnv("FAUCET_ADDRESS", vm.toString(faucet));
        vm.setEnv("FAUCET_DISPENSER_ADDRESS", vm.toString(legacy));
        vm.setEnv("GUARDIAN_ADDRESS", vm.toString(guard));
        vm.setEnv("FAUCET_DAILY_CAP", "40");
        vm.setEnv("FAUCET_ETH_FUND_WEI", "4000000000000000");
        vm.setEnv("SANDBOX_MAX_SWAP_WHOLE_USDG", "5000");
        vm.setEnv("USDG_DECIMALS", "6");
        vm.setEnv("ENABLE_SHOCK", "1");
    }

    function test_guardsExistOnlyInScriptAndHoldOnTestnet() public {
        string memory net = "robinhood-testnet";
        DeployV2Harness h = new DeployV2Harness();

        _env(net, ZERO, faucetAddr, ZERO, guardianAddr);
        vm.expectRevert(DeployV2.RelayerAddressRequired.selector);
        h.load(deployerAddr);

        _env(net, deployerAddr, faucetAddr, ZERO, guardianAddr);
        vm.expectRevert(DeployV2.RelayerAddressIsDeployer.selector);
        h.load(deployerAddr);

        _env(net, relayerAddr, ZERO, ZERO, guardianAddr);
        vm.expectRevert(DeployV2.FaucetAddressRequired.selector);
        h.load(deployerAddr);

        _env(net, relayerAddr, deployerAddr, ZERO, guardianAddr);
        vm.expectRevert(DeployV2.FaucetAddressIsDeployer.selector);
        h.load(deployerAddr);

        _env(net, relayerAddr, faucetAddr, ZERO, guardianAddr);
        h.load(deployerAddr);
        assertEq(h.cfgRelayer(), relayerAddr);
        assertEq(h.cfgDispenser(), faucetAddr);
        assertEq(h.cfgGuardian(), guardianAddr);
        assertEq(h.cfgCap(), 40);
        assertEq(h.cfgFund(), 40 * 0.0001 ether);
        assertEq(h.cfgFund(), 0.004 ether);
        assertEq(h.cfgMaxSwap(), 5000 * 1e6);

        _env("anvil", ZERO, ZERO, ZERO, deployerAddr);
        h.load(deployerAddr);
        assertEq(h.cfgRelayer(), deployerAddr);
        assertEq(h.cfgDispenser(), deployerAddr);

        _env("dry-local", deployerAddr, deployerAddr, ZERO, deployerAddr);
        h.load(deployerAddr);
        assertEq(h.cfgRelayer(), deployerAddr);
    }

    function test_deployedSetMatchesDefaults() public {
        DeployV2Harness h = new DeployV2Harness();
        _env("robinhood-testnet", relayerAddr, faucetAddr, ZERO, guardianAddr);
        h.load(address(h));
        vm.deal(address(h), 1 ether);
        h.deployAll();
        (address deskA, address faucetA, address[5] memory feedA, address usdgA) = h.addrs();

        assertEq(OracleDesk(deskA).maxSwapUsdg(), 5000 * 1e6);
        FengFaucet f = FengFaucet(payable(faucetA));
        assertEq(f.ethPerClaim(), 0.0001 ether);
        assertEq(f.dailyCap(), 40);
        assertEq(faucetA.balance, 0.004 ether);
        assertEq(f.usdgPerClaim(), 10_000e6);
        assertTrue(IAccessControl(faucetA).hasRole(f.DISPENSER_ROLE(), faucetAddr));
        assertFalse(IAccessControl(faucetA).hasRole(f.DISPENSER_ROLE(), address(h)));
        assertGt(usdgA.code.length, 0);
        for (uint256 i = 0; i < 5; i++) {
            FengAggregator a = FengAggregator(feedA[i]);
            assertTrue(a.hasRole(a.UPDATER_ROLE(), relayerAddr));
            assertTrue(a.hasRole(a.SHOCK_ROLE(), relayerAddr));
            assertFalse(a.hasRole(a.UPDATER_ROLE(), address(h)));
            assertEq(a.maxDeviationBps(), 1000);
            assertEq(a.maxShockBps(), 3000);
        }
    }
}
