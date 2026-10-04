// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISocialRegistry {
    event Followed(address indexed user, address indexed target);
    event Unfollowed(address indexed user, address indexed target);
    event ProfileSet(address indexed user, string handle, string bio);

    error ZeroAddress();
    error CannotFollowSelf();
    error AlreadyFollowing();
    error NotFollowing();
    error InvalidHandleLength();
    error InvalidHandleChar();
    error HandleTaken();
    error BioTooLong();

    function follow(address target) external;

    function unfollow(address target) external;

    function followerCount(address target) external view returns (uint256);

    function isFollowing(address user, address target) external view returns (bool);

    function followedBy(address user) external view returns (address[] memory targets);

    function setProfile(string calldata handle, string calldata bio) external;

    function profileOf(address user) external view returns (string memory handle, string memory bio);

    function ownerOfHandle(string calldata handle) external view returns (address owner);
}
