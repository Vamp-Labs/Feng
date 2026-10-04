// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

contract ChainlinkPriceOracle is IPriceOracle, Ownable {
    mapping(address => address) public feeds;

    error FeedNotSet(address token);
    error InvalidPrice(address token);

    event FeedSet(address indexed token, address indexed feed);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setFeed(address token, address feed) external onlyOwner {
        require(token != address(0) && feed != address(0), "zero address");
        feeds[token] = feed;
        emit FeedSet(token, feed);
    }

    function getPrice(address token) external view returns (uint256 price, uint256 updatedAt) {
        address feed = feeds[token];
        if (feed == address(0)) revert FeedNotSet(token);
        (, int256 answer,, uint256 updatedAt_,) = AggregatorV3Interface(feed).latestRoundData();
        if (answer <= 0) revert InvalidPrice(token);
        uint8 feedDecimals = AggregatorV3Interface(feed).decimals();
        price = _scaleTo18(uint256(answer), feedDecimals);
        updatedAt = updatedAt_;
    }

    function _scaleTo18(uint256 amount, uint8 fromDecimals) private pure returns (uint256) {
        if (fromDecimals == 18) return amount;
        if (fromDecimals < 18) return amount * 10 ** (18 - fromDecimals);
        return amount / 10 ** (fromDecimals - 18);
    }
}
