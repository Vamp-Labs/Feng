// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {SocialRegistry} from "../../../v2/SocialRegistry.sol";
import {SocialHandler} from "./SocialHandler.sol";

contract SocialRegistryInvariantTest is StdInvariant, Test {
    SocialRegistry internal reg;
    SocialHandler internal h;

    function setUp() public {
        reg = new SocialRegistry();
        h = new SocialHandler(reg);
        targetContract(address(h));
        bytes4[] memory sels = new bytes4[](3);
        sels[0] = SocialHandler.follow.selector;
        sels[1] = SocialHandler.unfollow.selector;
        sels[2] = SocialHandler.setProfile.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: sels}));
    }

    function afterInvariant() public view {
        assertGt(h.ghost_follows() + h.ghost_followReverts() + h.ghost_unfollows(), 0);
    }

    function invariant_noUnexpectedRevert() public view {
        assertFalse(h.ghost_unexpectedRevert());
    }

    function invariant_followerCountNeverNegativeAndMatchesGhost() public view {
        address[5] memory targets = h.targetsList();
        for (uint256 i = 0; i < targets.length; i++) {
            uint256 onChain = reg.followerCount(targets[i]);
            assertGe(onChain, 0);
            assertEq(onChain, h.ghost_followerCount(targets[i]));
        }
    }

    function invariant_isFollowingMatchesGhostForEveryPair() public view {
        address[6] memory actors = h.actorsList();
        address[5] memory targets = h.targetsList();
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < targets.length; j++) {
                assertEq(reg.isFollowing(actors[i], targets[j]), h.ghost_following(actors[i], targets[j]));
            }
        }
    }

    function invariant_followedByMatchesGhostCount() public view {
        address[6] memory actors = h.actorsList();
        address[5] memory targets = h.targetsList();
        for (uint256 i = 0; i < actors.length; i++) {
            address[] memory list = reg.followedBy(actors[i]);
            uint256 ghostCount;
            for (uint256 j = 0; j < targets.length; j++) {
                if (h.ghost_following(actors[i], targets[j])) ghostCount++;
            }
            assertEq(list.length, ghostCount);
            for (uint256 k = 0; k < list.length; k++) {
                assertTrue(reg.isFollowing(actors[i], list[k]));
                for (uint256 m = k + 1; m < list.length; m++) {
                    assertTrue(list[k] != list[m]);
                }
            }
        }
    }

    function invariant_followerCountEqualsSumOfFollowers() public view {
        address[6] memory actors = h.actorsList();
        address[5] memory targets = h.targetsList();
        for (uint256 j = 0; j < targets.length; j++) {
            uint256 sum;
            for (uint256 i = 0; i < actors.length; i++) {
                if (reg.isFollowing(actors[i], targets[j])) sum++;
            }
            assertEq(sum, reg.followerCount(targets[j]));
        }
    }

    function invariant_handleOwnershipIsUniqueAndMatchesGhost() public view {
        string[4] memory handles = h.handlePoolList();
        for (uint256 i = 0; i < handles.length; i++) {
            bytes32 handleHash = keccak256(bytes(handles[i]));
            assertEq(reg.ownerOfHandle(handles[i]), h.ghost_handleOwner(handleHash));
        }

        address[6] memory actors = h.actorsList();
        for (uint256 i = 0; i < handles.length; i++) {
            uint256 claimants;
            for (uint256 j = 0; j < actors.length; j++) {
                (string memory handle,) = reg.profileOf(actors[j]);
                if (keccak256(bytes(handle)) == keccak256(bytes(handles[i]))) claimants++;
            }
            assertLe(claimants, 1);
        }
    }

    function invariant_profileHandleMatchesGhost() public view {
        address[6] memory actors = h.actorsList();
        for (uint256 i = 0; i < actors.length; i++) {
            (string memory handle,) = reg.profileOf(actors[i]);
            assertEq(handle, h.ghost_handleOf(actors[i]));
        }
    }
}
