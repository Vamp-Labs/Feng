// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {SocialRegistry} from "../../../v2/SocialRegistry.sol";

contract SocialHandler is CommonBase, StdCheats, StdUtils {
    SocialRegistry public reg;

    uint256 public constant ACTOR_COUNT = 6;
    uint256 public constant TARGET_COUNT = 5;
    uint256 public constant HANDLE_COUNT = 4;

    address[ACTOR_COUNT] public actors;
    address[TARGET_COUNT] public targets;
    string[HANDLE_COUNT] public handlePool = ["aaa", "bbb", "ccc", "ddd"];

    mapping(address => mapping(address => bool)) public ghost_following;
    mapping(address => uint256) public ghost_followerCount;
    mapping(bytes32 => address) public ghost_handleOwner;
    mapping(address => string) public ghost_handleOf;

    uint256 public ghost_follows;
    uint256 public ghost_unfollows;
    uint256 public ghost_followReverts;
    uint256 public ghost_unfollowReverts;
    uint256 public ghost_profileSets;
    uint256 public ghost_profileReverts;
    bool public ghost_unexpectedRevert;

    constructor(SocialRegistry reg_) {
        reg = reg_;
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            actors[i] = address(uint160(uint256(keccak256(abi.encodePacked("social-actor", i)))));
        }
        for (uint256 i = 0; i < TARGET_COUNT; i++) {
            targets[i] = address(uint160(uint256(keccak256(abi.encodePacked("social-target", i)))));
        }
    }

    function follow(uint256 userSeed, uint256 targetSeed) external {
        address user = actors[bound(userSeed, 0, ACTOR_COUNT - 1)];
        address target = targets[bound(targetSeed, 0, TARGET_COUNT - 1)];

        vm.prank(user);
        try reg.follow(target) {
            if (ghost_following[user][target] || user == target) {
                ghost_unexpectedRevert = true;
            }
            ghost_following[user][target] = true;
            ghost_followerCount[target] += 1;
            ghost_follows += 1;
        } catch {
            bool expected = ghost_following[user][target] || user == target;
            if (!expected) ghost_unexpectedRevert = true;
            ghost_followReverts += 1;
        }
    }

    function unfollow(uint256 userSeed, uint256 targetSeed) external {
        address user = actors[bound(userSeed, 0, ACTOR_COUNT - 1)];
        address target = targets[bound(targetSeed, 0, TARGET_COUNT - 1)];

        vm.prank(user);
        try reg.unfollow(target) {
            if (!ghost_following[user][target]) ghost_unexpectedRevert = true;
            ghost_following[user][target] = false;
            ghost_followerCount[target] -= 1;
            ghost_unfollows += 1;
        } catch {
            if (ghost_following[user][target]) ghost_unexpectedRevert = true;
            ghost_unfollowReverts += 1;
        }
    }

    function setProfile(uint256 userSeed, uint256 handleSeed, uint256 bioSeed) external {
        address user = actors[bound(userSeed, 0, ACTOR_COUNT - 1)];
        string memory handle = handlePool[bound(handleSeed, 0, HANDLE_COUNT - 1)];
        string memory bio = bound(bioSeed, 0, 1) == 0 ? "" : "a mock bio for fuzzing";

        bytes32 handleHash = keccak256(bytes(handle));
        address currentOwner = ghost_handleOwner[handleHash];
        bool changingHandle = keccak256(bytes(ghost_handleOf[user])) != handleHash;
        bool shouldSucceed = !changingHandle || currentOwner == address(0);

        vm.prank(user);
        try reg.setProfile(handle, bio) {
            if (!shouldSucceed) ghost_unexpectedRevert = true;
            if (changingHandle) {
                bytes32 oldHash = keccak256(bytes(ghost_handleOf[user]));
                if (bytes(ghost_handleOf[user]).length != 0 && ghost_handleOwner[oldHash] == user) {
                    delete ghost_handleOwner[oldHash];
                }
                ghost_handleOwner[handleHash] = user;
            }
            ghost_handleOf[user] = handle;
            ghost_profileSets += 1;
        } catch {
            if (shouldSucceed) ghost_unexpectedRevert = true;
            ghost_profileReverts += 1;
        }
    }

    function actorsList() external view returns (address[ACTOR_COUNT] memory) {
        return actors;
    }

    function targetsList() external view returns (address[TARGET_COUNT] memory) {
        return targets;
    }

    function handlePoolList() external view returns (string[HANDLE_COUNT] memory) {
        return handlePool;
    }
}
