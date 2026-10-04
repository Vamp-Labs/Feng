// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../interfaces/AggregatorV3Interface.sol";

interface IFengAggregator is AggregatorV3Interface {
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event AnswerShocked(int256 indexed current, int256 indexed anchor, uint256 indexed roundId);
    event AnswerForced(int256 indexed current, uint256 indexed roundId, address indexed by);
    event ParamsSet(uint16 maxDeviationBps, uint16 maxShockBps);
    event ShockEnabledSet(bool enabled);

    error DeviationTooHigh(int256 answer, int256 anchor, uint16 maxDeviationBps);
    error ShockTooHigh(int256 answer, int256 anchor, uint16 maxShockBps);
    error ShockDisabled();
    error InvalidAnswer(int256 answer);
    error InvalidParams();

    function UPDATER_ROLE() external view returns (bytes32);
    function SHOCK_ROLE() external view returns (bytes32);
    function MAX_DEVIATION_CAP_BPS() external view returns (uint16);
    function MAX_SHOCK_CAP_BPS() external view returns (uint16);

    function anchorAnswer() external view returns (int256);
    function latestAnswer() external view returns (int256);
    function maxDeviationBps() external view returns (uint16);
    function maxShockBps() external view returns (uint16);
    function shockEnabled() external view returns (bool);

    function updateAnswer(int256 answer) external;
    function refresh() external;
    function shockAnswer(int256 answer) external;
    function forceAnswer(int256 answer) external;
    function setParams(uint16 maxDeviationBps_, uint16 maxShockBps_) external;
    function setShockEnabled(bool enabled) external;
}
