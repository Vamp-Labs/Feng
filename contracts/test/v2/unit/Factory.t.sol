// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2, VaultParams} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {IStrategyFactoryV2} from "../../../v2/interfaces/IStrategyFactoryV2.sol";
import {StrategyMeta} from "../../../v2/interfaces/IMarketplaceRegistryV2.sol";
import {StrategyFactoryV2} from "../../../v2/StrategyFactoryV2.sol";
import {IOracleDesk} from "../../../v2/interfaces/IOracleDesk.sol";
import {TestToken, NoReturnToken} from "../mocks/HostileTokens.sol";
import {HostileVenue} from "../mocks/HostileVenues.sol";

contract FactoryV2Test is DeployV2Helper {
    function setUp() public {
        _deployStack();
    }

    function _try(string memory name, string memory sym, Constituent[] memory c, uint16 maxW, uint256 iv, uint16 sl)
        internal
        returns (address v, address t)
    {
        vm.prank(creator);
        return factory.createStrategy(name, sym, c, maxW, iv, sl, _meta());
    }

    function _ok() internal view returns (Constituent[] memory) {
        return _two(address(stocks[0]), 5000, address(stocks[1]), 5000);
    }

    function _expect(bytes4 sel) internal {
        vm.expectPartialRevert(sel);
    }

    function test_constants() public view {
        assertEq(factory.MAX_DEPTH(), 2);
        assertEq(factory.MAX_CONSTITUENTS(), 6);
        assertEq(factory.MIN_WEIGHT_BPS(), 100);
        assertEq(factory.MAX_SLIPPAGE_BPS(), 500);
        assertEq(factory.MIN_REBALANCE_INTERVAL(), 1 hours);
        assertEq(factory.MAX_REBALANCE_INTERVAL(), 365 days);
        assertEq(factory.registry(), address(registry));
        assertEq(factory.priceOracle(), address(oracle));
        assertEq(factory.venue(), address(desk));
        assertEq(factory.usdg(), usdg);
        assertEq(factory.usdgDecimals(), usdgDec);
        assertEq(factory.guardian(), guardian);
        assertEq(factory.vaultDeployer(), address(deployer));
        assertEq(factory.maxPriceStaleness(), STALENESS);
    }

    function test_create_registersAndEmits() public {
        vm.recordLogs();
        (address v, address t) = _try("Alpha", "ALP", _ok(), 5000, 7 days, 100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(factory)
                    && logs[i].topics[0] == keccak256("StrategyCreated(address,address,address,uint8)")
            ) {
                found = true;
                assertEq(address(uint160(uint256(logs[i].topics[1]))), v);
                assertEq(address(uint160(uint256(logs[i].topics[2]))), t);
                assertEq(address(uint160(uint256(logs[i].topics[3]))), creator);
            }
        }
        assertTrue(found);
        assertEq(factory.vaultOf(t), v);
        assertTrue(registry.isRegistered(v));
        assertEq(registry.strategyCount(), 1);
        (address tok, address cr, uint8 d, uint256 at) = registry.getStrategyInfo(v);
        assertEq(tok, t);
        assertEq(cr, creator);
        assertEq(d, 1);
        assertEq(at, block.timestamp);
        assertEq(IStrategyVaultV2(v).guardian(), guardian);
        assertEq(IStrategyVaultV2(v).venue(), address(desk));
        assertEq(IStrategyVaultV2(v).maxSlippageBps(), 100);
        assertEq(IStrategyVaultV2(v).rebalanceInterval(), 7 days);
    }

    function test_err_emptyConstituents() public {
        Constituent[] memory c = new Constituent[](0);
        _expect(_sel("EmptyConstituents()"));
        _try("A", "AA", c, 5000, 7 days, 100);
    }

    function test_err_tooMany() public {
        Constituent[] memory c = new Constituent[](7);
        for (uint256 i = 0; i < 7; i++) {
            c[i] = Constituent({token: address(uint160(i + 1)), targetWeightBps: 1000, isStrategyToken: false});
        }
        _expect(_sel("TooManyConstituents()"));
        _try("A", "AA", c, 10_000, 7 days, 100);
    }

    function test_err_zeroAddressConstituent() public {
        Constituent[] memory c = _two(address(0), 5000, address(stocks[1]), 5000);
        _expect(_sel("ZeroAddressConstituent()"));
        _try("A", "AA", c, 5000, 7 days, 100);
    }

    function test_err_duplicate() public {
        Constituent[] memory c = _two(address(stocks[0]), 5000, address(stocks[0]), 5000);
        _expect(_sel("DuplicateConstituent()"));
        _try("A", "AA", c, 5000, 7 days, 100);
    }

    function test_err_usdgConstituent() public {
        Constituent[] memory c = _two(usdg, 5000, address(stocks[1]), 5000);
        _expect(_sel("ConstituentIsUsdg()"));
        _try("A", "AA", c, 5000, 7 days, 100);
    }

    function test_err_unsupportedConstituent() public {
        TestToken rogue = new TestToken("R", "R", 18);
        Constituent[] memory c = _two(address(rogue), 5000, address(stocks[1]), 5000);
        _expect(_sel("UnsupportedConstituent(address)"));
        _try("A", "AA", c, 5000, 7 days, 100);
    }

    function test_err_unsupportedConstituent_oracleOnlyOrVenueOnly() public {
        TestToken onlyOracle = new TestToken("R", "R", 18);
        vm.prank(admin);
        oracle.setFeed(address(onlyOracle), address(feeds[0]));
        Constituent[] memory c = _two(address(onlyOracle), 5000, address(stocks[1]), 5000);
        _expect(_sel("UnsupportedConstituent(address)"));
        _try("A", "AA", c, 5000, 7 days, 100);
        TestToken onlyVenue = new TestToken("V", "V", 18);
        vm.prank(admin);
        desk.setToken(address(onlyVenue), IOracleDesk.Mode.Inventory);
        c = _two(address(onlyVenue), 5000, address(stocks[1]), 5000);
        _expect(_sel("UnsupportedConstituent(address)"));
        _try("A", "AA", c, 5000, 7 days, 100);
    }

    function test_err_weightsSum() public {
        Constituent[] memory c = _two(address(stocks[0]), 5000, address(stocks[1]), 4000);
        _expect(_sel("WeightsMustSumTo10000()"));
        _try("A", "AA", c, 5000, 7 days, 100);
    }

    function test_err_weightTooSmall() public {
        Constituent[] memory c = _two(address(stocks[0]), 50, address(stocks[1]), 9950);
        _expect(_sel("WeightTooSmall(address)"));
        _try("A", "AA", c, 9950, 7 days, 100);
    }

    function test_err_maxWeightExceeded() public {
        _expect(_sel("MaxWeightExceeded()"));
        _try("A", "AA", _ok(), 4000, 7 days, 100);
    }

    function test_err_invalidMaxWeight() public {
        _expect(_sel("InvalidMaxWeight()"));
        _try("A", "AA", _ok(), 0, 7 days, 100);
        _expect(_sel("InvalidMaxWeight()"));
        _try("A", "AA", _ok(), 10_001, 7 days, 100);
    }

    function test_err_interval() public {
        _expect(_sel("InvalidInterval()"));
        _try("A", "AA", _ok(), 5000, 1 hours - 1, 100);
        _expect(_sel("InvalidInterval()"));
        _try("A", "AA", _ok(), 5000, 365 days + 1, 100);
        _try("A", "AA", _ok(), 5000, 1 hours, 100);
        _try("B", "BB", _ok(), 5000, 365 days, 100);
    }

    function test_err_slippage() public {
        _expect(_sel("InvalidMaxSlippage()"));
        _try("A", "AA", _ok(), 5000, 7 days, 0);
        _expect(_sel("InvalidMaxSlippage()"));
        _try("A", "AA", _ok(), 5000, 7 days, 501);
        _try("A", "AA", _ok(), 5000, 7 days, 500);
        _try("A", "AA", _ok(), 5000, 7 days, 1);
    }

    function test_err_nameSymbol() public {
        _expect(_sel("InvalidName()"));
        _try("", "AA", _ok(), 5000, 7 days, 100);
        _expect(_sel("InvalidName()"));
        _try("123456789012345678901234567890123456789012345678901", "AA", _ok(), 5000, 7 days, 100);
        _try("123456789012345678901234567890123456789012345678", "AA", _ok(), 5000, 7 days, 100);
        _expect(_sel("InvalidSymbol()"));
        _try("A", "A", _ok(), 5000, 7 days, 100);
        _expect(_sel("InvalidSymbol()"));
        _try("A", "ABCDEFGHIJK", _ok(), 5000, 7 days, 100);
        _try("A", "ABCDEFGHIJ", _ok(), 5000, 7 days, 100);
    }

    function test_err_unknownStrategyToken() public {
        Constituent[] memory c = new Constituent[](1);
        c[0] = Constituent({token: address(0xABCD), targetWeightBps: 10_000, isStrategyToken: true});
        _expect(_sel("UnknownStrategyToken()"));
        _try("A", "AA", c, 10_000, 7 days, 100);
    }

    function test_depth3Reverts() public {
        (, address t1) = _fiftyFifty();
        Constituent[] memory c2 = new Constituent[](1);
        c2[0] = Constituent({token: t1, targetWeightBps: 10_000, isStrategyToken: true});
        (address v2, address t2) = _try("D2", "D2", c2, 10_000, 7 days, 100);
        assertEq(IStrategyVaultV2(v2).depth(), 2);
        Constituent[] memory c3 = new Constituent[](1);
        c3[0] = Constituent({token: t2, targetWeightBps: 10_000, isStrategyToken: true});
        vm.prank(creator);
        try factory.createStrategy("D3", "D3", c3, 10_000, 7 days, 100, _meta()) {
            fail("depth 3 created");
        } catch (bytes memory r) {
            bytes4 s;
            assembly {
                s := mload(add(r, 32))
            }
            assertTrue(s == _sel("DepthExceeded()") || s == _sel("NestedTokenNotLeaf()"));
        }
    }

    function test_strategyFlagMismatchOnPlainToken() public {
        Constituent[] memory c = new Constituent[](1);
        c[0] = Constituent({token: address(stocks[0]), targetWeightBps: 10_000, isStrategyToken: true});
        _expect(_sel("UnknownStrategyToken()"));
        _try("A", "AA", c, 10_000, 7 days, 100);
    }

    function test_noGrantRoleCallsOnConstituents() public {
        NoReturnToken nrt = new NoReturnToken();
        _newInventoryToken(address(nrt), 10e8, 1e24);
        Constituent[] memory c = _two(address(nrt), 5000, address(stocks[1]), 5000);
        (address v,) = _try("NR", "NRT", c, 5000, 7 days, 100);
        assertTrue(registry.isRegistered(v));
    }

    function test_realTokenWithoutMinterRoleAccepted() public {
        TestToken real = new TestToken("REAL", "REAL", 18);
        _newInventoryToken(address(real), 10e8, 1e24);
        Constituent[] memory c = _two(address(real), 5000, address(stocks[1]), 5000);
        (address v,) = _try("RL", "RL", c, 5000, 7 days, 100);
        assertFalse(_hasRole(address(real), real.MINTER_ROLE(), v));
        assertFalse(_hasRole(address(real), real.MINTER_ROLE(), address(factory)));
    }

    function test_vaultCreatedByStrangerIsNotRegistered() public {
        VaultParams memory p;
        p.name = "S";
        p.symbol = "SS";
        p.usdg = usdg;
        p.oracle = address(oracle);
        p.venue = address(desk);
        p.guardian = attacker;
        p.constituents = _ok();
        p.maxWeightBps = 5000;
        p.maxSlippageBps = 100;
        p.depth = 1;
        p.rebalanceInterval = 7 days;
        p.maxPriceStaleness = STALENESS;
        vm.prank(attacker);
        (address v,) = deployer.deploy(p);
        assertFalse(registry.isRegistered(v));
        assertEq(factory.vaultOf(IStrategyVaultV2(v).token()), address(0));
        _mintUsdg(attacker, 1000 * U);
        vm.startPrank(attacker);
        IERC20(usdg).approve(v, 1000 * U);
        vm.expectPartialRevert(_sel("NotVault(address)"));
        IStrategyVaultV2(v).deposit(1000 * U, attacker, 0);
        vm.stopPrank();
        Constituent[] memory c = new Constituent[](1);
        c[0] = Constituent({token: IStrategyVaultV2(v).token(), targetWeightBps: 10_000, isStrategyToken: true});
        _expect(_sel("UnknownStrategyToken()"));
        _try("X", "XX", c, 10_000, 7 days, 100);
    }

    function test_maxWeightBand() public {
        (IStrategyVaultV2 v,) = _threeAsset();
        assertEq(v.effectiveMaxWeightBps(0), 4500);
        assertEq(v.effectiveMaxWeightBps(1), 4500);
        assertEq(v.effectiveMaxWeightBps(2), 4500);
        (IStrategyVaultV2 w,) = _fiftyFifty();
        assertEq(w.effectiveMaxWeightBps(0), 5010);
        Constituent[] memory c = new Constituent[](1);
        c[0] = Constituent({token: address(stocks[0]), targetWeightBps: 10_000, isStrategyToken: false});
        (address s,) = _try("S", "SS", c, 10_000, 7 days, 100);
        assertEq(IStrategyVaultV2(s).effectiveMaxWeightBps(0), 10_000);
        Constituent[] memory c2 = _two(address(stocks[0]), 9000, address(stocks[1]), 1000);
        (address q,) = _try("Q", "QQ", c2, 9995, 7 days, 100);
        assertEq(IStrategyVaultV2(q).effectiveMaxWeightBps(0), 9995);
    }

    function test_ctor_validation() public {
        vm.expectRevert();
        new StrategyFactoryV2(address(0), address(oracle), address(desk), usdg, guardian, address(deployer), STALENESS);
        vm.expectRevert();
        new StrategyFactoryV2(
            address(registry), address(0), address(desk), usdg, guardian, address(deployer), STALENESS
        );
        vm.expectRevert();
        new StrategyFactoryV2(
            address(registry), address(oracle), address(0), usdg, guardian, address(deployer), STALENESS
        );
        vm.expectRevert();
        new StrategyFactoryV2(
            address(registry), address(oracle), address(desk), address(0), guardian, address(deployer), STALENESS
        );
        vm.expectRevert();
        new StrategyFactoryV2(
            address(registry), address(oracle), address(desk), usdg, address(0), address(deployer), STALENESS
        );
        vm.expectRevert();
        new StrategyFactoryV2(address(registry), address(oracle), address(desk), usdg, guardian, address(0), STALENESS);
        vm.expectRevert();
        new StrategyFactoryV2(address(registry), address(oracle), address(desk), usdg, guardian, address(deployer), 0);
    }

    function test_ctor_venueUsdgMismatch() public {
        HostileVenue hv = new HostileVenue(address(0xdead));
        vm.expectPartialRevert(_sel("VenueUsdgMismatch()"));
        new StrategyFactoryV2(
            address(registry), address(oracle), address(hv), usdg, guardian, address(deployer), STALENESS
        );
    }

    function test_ctor_unsupportedUsdgDecimals() public {
        TestToken big = new TestToken("B", "B", 19);
        HostileVenue hv = new HostileVenue(address(big));
        vm.expectPartialRevert(_sel("UnsupportedUsdgDecimals(uint8)"));
        new StrategyFactoryV2(
            address(registry), address(oracle), address(hv), address(big), guardian, address(deployer), STALENESS
        );
    }

    function test_factoryNeedsFactoryRole() public {
        StrategyFactoryV2 f2 = new StrategyFactoryV2(
            address(registry), address(oracle), address(desk), usdg, guardian, address(deployer), STALENESS
        );
        vm.prank(creator);
        vm.expectRevert();
        f2.createStrategy("A", "AA", _ok(), 5000, 7 days, 100, _meta());
    }

    function test_createWithStrategyChild_depthRecorded() public {
        (IStrategyVaultV2 c, address ct) = _fiftyFifty();
        (IStrategyVaultV2 p,) = _nested(c, ct);
        assertEq(p.depth(), 2);
        assertEq(c.depth(), 1);
    }
}
