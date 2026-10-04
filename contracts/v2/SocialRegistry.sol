// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISocialRegistry} from "./interfaces/ISocialRegistry.sol";

contract SocialRegistry is ISocialRegistry {
    uint256 public constant MIN_HANDLE_BYTES = 3;
    uint256 public constant MAX_HANDLE_BYTES = 20;
    uint256 public constant MAX_BIO_BYTES = 160;

    mapping(address => mapping(address => bool)) private _following;
    mapping(address => address[]) private _followedList;
    mapping(address => mapping(address => uint256)) private _followedIndex;
    mapping(address => uint256) private _followerCount;

    mapping(bytes32 => address) private _handleOwner;
    mapping(address => string) private _handleOf;
    mapping(address => string) private _bioOf;

    function follow(address target) external {
        if (target == address(0)) revert ZeroAddress();
        if (target == msg.sender) revert CannotFollowSelf();
        if (_following[msg.sender][target]) revert AlreadyFollowing();
        _following[msg.sender][target] = true;
        _followedList[msg.sender].push(target);
        _followedIndex[msg.sender][target] = _followedList[msg.sender].length;
        _followerCount[target] += 1;
        emit Followed(msg.sender, target);
    }

    function unfollow(address target) external {
        if (!_following[msg.sender][target]) revert NotFollowing();
        _following[msg.sender][target] = false;

        address[] storage list = _followedList[msg.sender];
        uint256 idx1 = _followedIndex[msg.sender][target];
        uint256 lastIdx1 = list.length;
        if (idx1 != lastIdx1) {
            address lastTarget = list[lastIdx1 - 1];
            list[idx1 - 1] = lastTarget;
            _followedIndex[msg.sender][lastTarget] = idx1;
        }
        list.pop();
        delete _followedIndex[msg.sender][target];

        _followerCount[target] -= 1;
        emit Unfollowed(msg.sender, target);
    }

    function followerCount(address target) external view returns (uint256) {
        return _followerCount[target];
    }

    function isFollowing(address user, address target) external view returns (bool) {
        return _following[user][target];
    }

    function followedBy(address user) external view returns (address[] memory targets) {
        return _followedList[user];
    }

    function setProfile(string calldata handle, string calldata bio) external {
        bytes calldata handleBytes = bytes(handle);
        uint256 handleLen = handleBytes.length;
        if (handleLen < MIN_HANDLE_BYTES || handleLen > MAX_HANDLE_BYTES) revert InvalidHandleLength();
        if (bytes(bio).length > MAX_BIO_BYTES) revert BioTooLong();
        _validateHandleChars(handleBytes);

        bytes32 newHash = keccak256(handleBytes);
        string memory oldHandle = _handleOf[msg.sender];
        bool changingHandle = bytes(oldHandle).length == 0 || keccak256(bytes(oldHandle)) != newHash;

        if (changingHandle) {
            if (_handleOwner[newHash] != address(0)) revert HandleTaken();
            if (bytes(oldHandle).length != 0) {
                delete _handleOwner[keccak256(bytes(oldHandle))];
            }
            _handleOwner[newHash] = msg.sender;
        }

        _handleOf[msg.sender] = handle;
        _bioOf[msg.sender] = bio;
        emit ProfileSet(msg.sender, handle, bio);
    }

    function profileOf(address user) external view returns (string memory handle, string memory bio) {
        return (_handleOf[user], _bioOf[user]);
    }

    function ownerOfHandle(string calldata handle) external view returns (address owner) {
        return _handleOwner[keccak256(bytes(handle))];
    }

    function _validateHandleChars(bytes calldata h) private pure {
        for (uint256 i = 0; i < h.length; i++) {
            bytes1 ch = h[i];
            bool ok = (ch >= 0x61 && ch <= 0x7a) || (ch >= 0x30 && ch <= 0x39) || ch == 0x5f || ch == 0x2d;
            if (!ok) revert InvalidHandleChar();
        }
    }
}
