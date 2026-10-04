// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFengAggregator} from "../interfaces/IFengAggregator.sol";

contract FengAggregator is IFengAggregator, AccessControl {
    uint256 private constant BPS = 10_000;

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant SHOCK_ROLE = keccak256("SHOCK_ROLE");
    uint16 public constant MAX_DEVIATION_CAP_BPS = 5000;
    uint16 public constant MAX_SHOCK_CAP_BPS = 5000;
    uint256 public constant ANCHOR_WINDOW = 1 hours;

    uint8 private immutable _decimals;
    string private _description;

    int256 public latestAnswer;
    int256 public anchorAnswer;
    uint256 private _updatedAt;
    uint256 public anchorSetAt;
    uint80 private _roundId;
    uint16 public maxDeviationBps;
    uint16 public maxShockBps;
    bool public shockEnabled;

    constructor(
        address admin,
        uint8 decimals_,
        string memory description_,
        int256 initialAnswer,
        uint16 maxDeviationBps_,
        uint16 maxShockBps_
    ) {
        if (admin == address(0)) revert InvalidParams();
        if (initialAnswer <= 0) revert InvalidAnswer(initialAnswer);
        _checkParams(maxDeviationBps_, maxShockBps_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _decimals = decimals_;
        _description = description_;
        maxDeviationBps = maxDeviationBps_;
        maxShockBps = maxShockBps_;
        latestAnswer = initialAnswer;
        anchorAnswer = initialAnswer;
        _roundId = 1;
        _updatedAt = block.timestamp;
        anchorSetAt = block.timestamp;
        emit ParamsSet(maxDeviationBps_, maxShockBps_);
        emit AnswerUpdated(initialAnswer, 1, block.timestamp);
    }

    function updateAnswer(int256 answer) external onlyRole(UPDATER_ROLE) {
        if (answer <= 0) revert InvalidAnswer(answer);
        int256 anchor = anchorAnswer;
        if (_distance(answer, anchor) > _bound(anchor, maxDeviationBps)) {
            revert DeviationTooHigh(answer, anchor, maxDeviationBps);
        }
        if (block.timestamp >= anchorSetAt + ANCHOR_WINDOW) {
            anchorAnswer = answer;
            anchorSetAt = block.timestamp;
        }
        _push(answer);
    }

    function refresh() external onlyRole(UPDATER_ROLE) {
        _push(latestAnswer);
    }

    function shockAnswer(int256 answer) external onlyRole(SHOCK_ROLE) {
        if (!shockEnabled) revert ShockDisabled();
        if (answer <= 0) revert InvalidAnswer(answer);
        int256 anchor = anchorAnswer;
        if (_distance(answer, anchor) > _bound(anchor, maxShockBps)) {
            revert ShockTooHigh(answer, anchor, maxShockBps);
        }
        uint256 round = _push(answer);
        emit AnswerShocked(answer, anchor, round);
    }

    function forceAnswer(int256 answer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (answer <= 0) revert InvalidAnswer(answer);
        anchorAnswer = answer;
        anchorSetAt = block.timestamp;
        uint256 round = _push(answer);
        emit AnswerForced(answer, round, msg.sender);
    }

    function setParams(uint16 maxDeviationBps_, uint16 maxShockBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _checkParams(maxDeviationBps_, maxShockBps_);
        maxDeviationBps = maxDeviationBps_;
        maxShockBps = maxShockBps_;
        emit ParamsSet(maxDeviationBps_, maxShockBps_);
    }

    function setShockEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        shockEnabled = enabled;
        emit ShockEnabledSet(enabled);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = _roundId;
        return (roundId, latestAnswer, _updatedAt, _updatedAt, roundId);
    }

    function _push(int256 answer) private returns (uint256 round) {
        round = uint256(_roundId) + 1;
        _roundId = uint80(round);
        latestAnswer = answer;
        _updatedAt = block.timestamp;
        emit AnswerUpdated(answer, round, block.timestamp);
    }

    function _distance(int256 a, int256 b) private pure returns (uint256) {
        return a >= b ? uint256(a - b) : uint256(b - a);
    }

    function _bound(int256 anchor, uint16 bps) private pure returns (uint256) {
        return Math.mulDiv(uint256(anchor), bps, BPS);
    }

    function _checkParams(uint16 maxDeviationBps_, uint16 maxShockBps_) private pure {
        if (
            maxDeviationBps_ == 0 || maxDeviationBps_ > MAX_DEVIATION_CAP_BPS || maxShockBps_ < maxDeviationBps_
                || maxShockBps_ > MAX_SHOCK_CAP_BPS
        ) revert InvalidParams();
    }
}
