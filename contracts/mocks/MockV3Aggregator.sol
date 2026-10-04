// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 private immutable _decimals;
    int256 private _latestAnswer;
    uint256 private _latestTimestamp;
    uint80 private _latestRound;

    constructor(uint8 decimals_, int256 initialAnswer) {
        _decimals = decimals_;
        _pushRound(initialAnswer, block.timestamp);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "MockV3Aggregator";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function updateAnswer(int256 answer) external {
        _pushRound(answer, block.timestamp);
    }

    function updateRoundData(int256 answer, uint256 updatedAt_) external {
        _pushRound(answer, updatedAt_);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_latestRound, _latestAnswer, _latestTimestamp, _latestTimestamp, _latestRound);
    }

    function _pushRound(int256 answer, uint256 updatedAt_) private {
        _latestRound += 1;
        _latestAnswer = answer;
        _latestTimestamp = updatedAt_;
    }
}
