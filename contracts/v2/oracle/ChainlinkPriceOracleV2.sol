// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "../../interfaces/AggregatorV3Interface.sol";
import {IPriceOracleV2} from "../interfaces/IPriceOracleV2.sol";

interface IChainlinkPriceOracleV2Admin {
    event FeedSet(address indexed token, address indexed feed);
    event FeedRemoved(address indexed token);

    error FeedNotSet(address token);
    error InvalidPrice(address token);
    error ZeroAddress();

    function feeds(address token) external view returns (address);
    function setFeed(address token, address feed) external;
    function removeFeed(address token) external;
}

contract ChainlinkPriceOracleV2 is IPriceOracleV2, IChainlinkPriceOracleV2Admin, Ownable {
    uint8 private constant PRICE_DECIMALS = 18;

    mapping(address => address) public feeds;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setFeed(address token, address feed) external onlyOwner {
        if (token == address(0) || feed == address(0)) revert ZeroAddress();
        feeds[token] = feed;
        emit FeedSet(token, feed);
    }

    function removeFeed(address token) external onlyOwner {
        if (feeds[token] == address(0)) revert FeedNotSet(token);
        delete feeds[token];
        emit FeedRemoved(token);
    }

    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt) {
        address feed = feeds[token];
        if (feed == address(0)) revert FeedNotSet(token);
        (, int256 answer,, uint256 updatedAt_,) = AggregatorV3Interface(feed).latestRoundData();
        if (answer <= 0) revert InvalidPrice(token);
        price = _scaleTo18(uint256(answer), AggregatorV3Interface(feed).decimals());
        updatedAt = updatedAt_;
    }

    function isSupported(address token) external view returns (bool) {
        return feeds[token] != address(0);
    }

    function priceDecimals() external pure returns (uint8) {
        return PRICE_DECIMALS;
    }

    function _scaleTo18(uint256 amount, uint8 fromDecimals) private pure returns (uint256) {
        if (fromDecimals == PRICE_DECIMALS) return amount;
        if (fromDecimals < PRICE_DECIMALS) return amount * 10 ** (PRICE_DECIMALS - fromDecimals);
        return amount / 10 ** (fromDecimals - PRICE_DECIMALS);
    }
}
