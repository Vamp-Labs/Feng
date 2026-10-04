// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployV2Helper} from "../helpers/DeployV2Helper.sol";
import {Constituent} from "../../../interfaces/IStrategyVault.sol";
import {IStrategyVaultV2, VaultParams} from "../../../v2/interfaces/IStrategyVaultV2.sol";
import {TestToken} from "../mocks/HostileTokens.sol";

contract GasCeilingsTest is DeployV2Helper {
    IStrategyVaultV2 internal v;

    function setUp() public {
        _deployStack();
        _newStock("S3", 18, 120e8);
        _newStock("S4", 18, 90e8);
        _newStock("S5", 18, 60e8);
        address[] memory t = new address[](6);
        uint16[] memory w = new uint16[](6);
        for (uint256 i = 0; i < 6; i++) {
            t[i] = address(stocks[i]);
            w[i] = i < 4 ? 1700 : 1600;
        }
        (v,) = _create("SIX", _cons(t, w), 2000, 1 days);
        _deposit(v, alice, 10_000 * U);
    }

    function test_gas_deposit() public {
        _mintUsdg(bob, 1000 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(v), 1000 * U);
        uint256 g = gasleft();
        v.deposit(1000 * U, bob, 0);
        g -= gasleft();
        vm.stopPrank();
        assertLe(g, 1_800_000);
    }

    function test_gas_depositInKind() public {
        stocks[0].mint(bob, 1e15);
        vm.startPrank(bob);
        stocks[0].approve(address(v), 1e15);
        uint256 g = gasleft();
        v.depositInKind(address(stocks[0]), 1e15, bob, 0);
        g -= gasleft();
        vm.stopPrank();
        assertLe(g, 600_000);
    }

    function test_gas_redeem() public {
        uint256 s = IERC20(v.token()).balanceOf(alice) / 2;
        vm.prank(alice);
        uint256 g = gasleft();
        v.redeem(s, alice, alice, 0);
        g -= gasleft();
        assertLe(g, 1_800_000);
    }

    function test_gas_redeemInKind() public {
        uint256 s = IERC20(v.token()).balanceOf(alice) / 2;
        vm.prank(alice);
        uint256 g = gasleft();
        v.redeemInKind(s, alice, alice);
        g -= gasleft();
        assertLe(g, 700_000);
    }

    function test_gas_checkpoint() public {
        vm.warp(block.timestamp + 31 minutes);
        _refreshAll();
        uint256 g = gasleft();
        v.checkpoint();
        g -= gasleft();
        assertLe(g, 300_000);
    }

    function test_gas_executeRebalanceAllLegs() public {
        _setPrice(0, 460e8);
        _setPrice(1, 213e8);
        _setPrice(2, 115e8);
        _setPrice(3, 138e8);
        _setPrice(4, 78e8);
        _setPrice(5, 69e8);
        _skewAndAge(1 days);
        uint256 g = gasleft();
        v.executeRebalance();
        g -= gasleft();
        assertLe(g, 2_200_000);
    }

    function test_gas_createStrategy() public {
        address[] memory t = new address[](6);
        uint16[] memory w = new uint16[](6);
        for (uint256 i = 0; i < 6; i++) {
            t[i] = address(stocks[i]);
            w[i] = i < 4 ? 1700 : 1600;
        }
        Constituent[] memory c = _cons(t, w);
        vm.prank(creator);
        uint256 g = gasleft();
        factory.createStrategy("G", "GG", c, 2000, 1 days, 100, _meta());
        g -= gasleft();
        assertLe(g, 6_500_000);
    }

    function test_gas_vaultDeployer() public {
        VaultParams memory p;
        p.name = "S";
        p.symbol = "SS";
        p.usdg = usdg;
        p.oracle = address(oracle);
        p.venue = address(desk);
        p.guardian = guardian;
        Constituent[] memory c = new Constituent[](6);
        for (uint256 i = 0; i < 6; i++) {
            c[i] =
                Constituent({token: address(stocks[i]), targetWeightBps: i < 4 ? 1700 : 1600, isStrategyToken: false});
        }
        p.constituents = c;
        p.maxWeightBps = 2000;
        p.maxSlippageBps = 100;
        p.depth = 1;
        p.rebalanceInterval = 1 days;
        p.maxPriceStaleness = STALENESS;
        uint256 g = gasleft();
        deployer.deploy(p);
        g -= gasleft();
        assertLe(g, 5_500_000);
    }

    function test_gas_depth2Deposit() public {
        (IStrategyVaultV2 c1, address t1) = _fiftyFifty();
        Constituent[] memory c = new Constituent[](3);
        c[0] = Constituent({token: t1, targetWeightBps: 4000, isStrategyToken: true});
        c[1] = Constituent({token: address(stocks[2]), targetWeightBps: 3000, isStrategyToken: false});
        c[2] = Constituent({token: address(stocks[3]), targetWeightBps: 3000, isStrategyToken: false});
        c1;
        (IStrategyVaultV2 p,) = _create("P2", c, 4000, 1 days);
        _mintUsdg(bob, 1000 * U);
        vm.startPrank(bob);
        IERC20(usdg).approve(address(p), 1000 * U);
        uint256 g = gasleft();
        p.deposit(1000 * U, bob, 0);
        g -= gasleft();
        vm.stopPrank();
        assertLe(g, 3_200_000);
    }
}
