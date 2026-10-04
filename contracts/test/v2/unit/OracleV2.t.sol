// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChainlinkPriceOracleV2} from "../../../v2/oracle/ChainlinkPriceOracleV2.sol";
import {MockV3Aggregator} from "../../../mocks/MockV3Aggregator.sol";
import {FengAggregator} from "../../../v2/oracle/FengAggregator.sol";

contract OracleV2Test is Test {
    ChainlinkPriceOracleV2 internal oracle;
    address internal owner = makeAddr("owner");
    address internal tok = makeAddr("tok");

    function setUp() public {
        vm.warp(1_700_000_000);
        oracle = new ChainlinkPriceOracleV2(owner);
    }

    function test_isSupportedAndDecimals() public {
        assertFalse(oracle.isSupported(tok));
        assertEq(oracle.priceDecimals(), 18);
        MockV3Aggregator f = new MockV3Aggregator(8, 400e8);
        vm.prank(owner);
        oracle.setFeed(tok, address(f));
        assertTrue(oracle.isSupported(tok));
        assertEq(oracle.feeds(tok), address(f));
        (uint256 p, uint256 u) = oracle.getPrice(tok);
        assertEq(p, 400e18);
        assertEq(u, block.timestamp);
    }

    function test_scalesOtherDecimals() public {
        MockV3Aggregator f6 = new MockV3Aggregator(6, 400e6);
        MockV3Aggregator f18 = new MockV3Aggregator(18, 400e18);
        address t2 = makeAddr("t2");
        vm.startPrank(owner);
        oracle.setFeed(tok, address(f6));
        oracle.setFeed(t2, address(f18));
        vm.stopPrank();
        (uint256 p1,) = oracle.getPrice(tok);
        (uint256 p2,) = oracle.getPrice(t2);
        assertEq(p1, 400e18);
        assertEq(p2, 400e18);
    }

    function test_feedNotSet() public {
        vm.expectRevert(abi.encodeWithSignature("FeedNotSet(address)", tok));
        oracle.getPrice(tok);
    }

    function test_invalidPrice() public {
        MockV3Aggregator f = new MockV3Aggregator(8, 0);
        vm.prank(owner);
        oracle.setFeed(tok, address(f));
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice(address)", tok));
        oracle.getPrice(tok);
        f.updateAnswer(-1);
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice(address)", tok));
        oracle.getPrice(tok);
    }

    function test_removeFeed() public {
        MockV3Aggregator f = new MockV3Aggregator(8, 400e8);
        vm.startPrank(owner);
        oracle.setFeed(tok, address(f));
        oracle.removeFeed(tok);
        vm.stopPrank();
        assertFalse(oracle.isSupported(tok));
        vm.expectRevert(abi.encodeWithSignature("FeedNotSet(address)", tok));
        oracle.getPrice(tok);
    }

    function test_adminGatingAndZero() public {
        vm.prank(makeAddr("rnd"));
        vm.expectRevert();
        oracle.setFeed(tok, address(1));
        vm.prank(makeAddr("rnd"));
        vm.expectRevert();
        oracle.removeFeed(tok);
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        oracle.setFeed(tok, address(0));
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        oracle.setFeed(address(0), address(1));
        vm.stopPrank();
    }

    function test_worksWithFengAggregator() public {
        FengAggregator f = new FengAggregator(owner, 8, "X", 250e8, 1500, 3000);
        vm.prank(owner);
        oracle.setFeed(tok, address(f));
        (uint256 p,) = oracle.getPrice(tok);
        assertEq(p, 250e18);
    }
}
