// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ChainlinkPriceOracle} from "../oracle/ChainlinkPriceOracle.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract ChainlinkPriceOracleTest is Test {
    ChainlinkPriceOracle internal oracle;
    MockV3Aggregator internal feed8;
    MockV3Aggregator internal feed18;
    address internal owner = makeAddr("owner");
    address internal asset8 = makeAddr("asset8");
    address internal asset18 = makeAddr("asset18");

    function setUp() public {
        vm.startPrank(owner);
        oracle = new ChainlinkPriceOracle(owner);
        feed8 = new MockV3Aggregator(8, int256(250e8));
        feed18 = new MockV3Aggregator(18, int256(250e18));
        oracle.setFeed(asset8, address(feed8));
        oracle.setFeed(asset18, address(feed18));
        vm.stopPrank();
    }

    function test_getPrice_scalesFeedDecimalsTo18() public view {
        (uint256 price8,) = oracle.getPrice(asset8);
        (uint256 price18,) = oracle.getPrice(asset18);
        assertEq(price8, 250e18);
        assertEq(price18, 250e18);
    }

    function test_getPrice_revertsWhenFeedNotSet() public {
        address unknown = makeAddr("unknown");
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.FeedNotSet.selector, unknown));
        oracle.getPrice(unknown);
    }

    function test_setFeed_onlyOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, makeAddr("notOwner"))
        );
        oracle.setFeed(asset8, address(feed8));
    }

    function test_getPrice_revertsOnNonPositiveAnswer() public {
        vm.prank(owner);
        feed8.updateAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.InvalidPrice.selector, asset8));
        oracle.getPrice(asset8);
    }
}
