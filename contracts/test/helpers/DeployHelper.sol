// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDG} from "../../mocks/MockUSDG.sol";
import {MockStockToken} from "../../mocks/MockStockToken.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {ChainlinkPriceOracle} from "../../oracle/ChainlinkPriceOracle.sol";
import {MarketplaceRegistry} from "../../MarketplaceRegistry.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {RebalanceEngine} from "../../RebalanceEngine.sol";
import {Constituent} from "../../interfaces/IStrategyVault.sol";

contract DeployHelper is Test {
    uint256 internal constant MAX_PRICE_STALENESS = 24 hours;

    address internal admin = makeAddr("admin");

    MockUSDG internal usdg;
    MockStockToken internal tsla;
    MockStockToken internal amzn;
    MockV3Aggregator internal usdgFeed;
    MockV3Aggregator internal tslaFeed;
    MockV3Aggregator internal amznFeed;
    ChainlinkPriceOracle internal oracle;
    MarketplaceRegistry internal registry;
    StrategyFactory internal factory;
    RebalanceEngine internal engine;

    function _deployCore() internal {
        vm.startPrank(admin);

        usdg = new MockUSDG(admin);
        tsla = new MockStockToken("Mock TSLA", "TSLA", admin, 1e18);
        amzn = new MockStockToken("Mock AMZN", "AMZN", admin, 1e18);

        usdgFeed = new MockV3Aggregator(8, int256(1e8));
        tslaFeed = new MockV3Aggregator(8, int256(250e8));
        amznFeed = new MockV3Aggregator(8, int256(180e8));

        oracle = new ChainlinkPriceOracle(admin);
        oracle.setFeed(address(usdg), address(usdgFeed));
        oracle.setFeed(address(tsla), address(tslaFeed));
        oracle.setFeed(address(amzn), address(amznFeed));

        registry = new MarketplaceRegistry(admin);
        factory = new StrategyFactory(address(registry), address(oracle), address(usdg), MAX_PRICE_STALENESS);
        engine = new RebalanceEngine(address(registry));

        registry.grantRole(registry.FACTORY_ROLE(), address(factory));
        tsla.grantRole(tsla.DEFAULT_ADMIN_ROLE(), address(factory));
        amzn.grantRole(amzn.DEFAULT_ADMIN_ROLE(), address(factory));

        vm.stopPrank();
    }

    function _singleAssetConstituents(address assetToken) internal pure returns (Constituent[] memory c) {
        c = new Constituent[](1);
        c[0] = Constituent({token: assetToken, targetWeightBps: 10_000, isStrategyToken: false});
    }

    function _twoAssetConstituents(address token0, uint16 weight0, address token1, uint16 weight1)
        internal
        pure
        returns (Constituent[] memory c)
    {
        c = new Constituent[](2);
        c[0] = Constituent({token: token0, targetWeightBps: weight0, isStrategyToken: false});
        c[1] = Constituent({token: token1, targetWeightBps: weight1, isStrategyToken: false});
    }

    function _mintUsdg(address to, uint256 amount) internal {
        vm.prank(admin);
        usdg.mint(to, amount);
    }

    function _refreshFeeds() internal {
        (, int256 usdgPrice,,,) = usdgFeed.latestRoundData();
        (, int256 tslaPrice,,,) = tslaFeed.latestRoundData();
        (, int256 amznPrice,,,) = amznFeed.latestRoundData();
        vm.startPrank(admin);
        usdgFeed.updateAnswer(usdgPrice);
        tslaFeed.updateAnswer(tslaPrice);
        amznFeed.updateAnswer(amznPrice);
        vm.stopPrank();
    }
}
