// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SocialRegistry} from "../../../v2/SocialRegistry.sol";

contract SocialRegistryTest is Test {
    SocialRegistry internal reg;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal vaultA = makeAddr("vaultA");
    address internal vaultB = makeAddr("vaultB");

    function setUp() public {
        reg = new SocialRegistry();
    }

    function _sel(string memory sig) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(sig)));
    }


    function test_follow_increasesCountAndState() public {
        vm.prank(alice);
        reg.follow(vaultA);
        assertTrue(reg.isFollowing(alice, vaultA));
        assertEq(reg.followerCount(vaultA), 1);
        address[] memory list = reg.followedBy(alice);
        assertEq(list.length, 1);
        assertEq(list[0], vaultA);
    }

    function test_follow_zeroAddressReverts() public {
        vm.prank(alice);
        vm.expectPartialRevert(_sel("ZeroAddress()"));
        reg.follow(address(0));
    }

    function test_follow_selfReverts() public {
        vm.prank(alice);
        vm.expectPartialRevert(_sel("CannotFollowSelf()"));
        reg.follow(alice);
    }

    function test_follow_doubleFollowReverts() public {
        vm.startPrank(alice);
        reg.follow(vaultA);
        vm.expectPartialRevert(_sel("AlreadyFollowing()"));
        reg.follow(vaultA);
        vm.stopPrank();
        assertEq(reg.followerCount(vaultA), 1);
    }

    function test_unfollow_notFollowingReverts() public {
        vm.prank(alice);
        vm.expectPartialRevert(_sel("NotFollowing()"));
        reg.unfollow(vaultA);
    }

    function test_unfollow_restoresState() public {
        vm.startPrank(alice);
        reg.follow(vaultA);
        reg.unfollow(vaultA);
        vm.stopPrank();
        assertFalse(reg.isFollowing(alice, vaultA));
        assertEq(reg.followerCount(vaultA), 0);
        assertEq(reg.followedBy(alice).length, 0);
    }

    function test_followThenUnfollowThenFollow_restoresExactState() public {
        vm.startPrank(alice);
        reg.follow(vaultA);
        reg.unfollow(vaultA);
        reg.follow(vaultA);
        vm.stopPrank();
        assertTrue(reg.isFollowing(alice, vaultA));
        assertEq(reg.followerCount(vaultA), 1);
        assertEq(reg.followedBy(alice).length, 1);
    }

    function test_unfollow_middleOfListSwapsCorrectly() public {
        vm.startPrank(alice);
        reg.follow(vaultA);
        reg.follow(vaultB);
        reg.follow(carol);
        reg.unfollow(vaultB);
        vm.stopPrank();
        address[] memory list = reg.followedBy(alice);
        assertEq(list.length, 2);
        assertTrue(reg.isFollowing(alice, vaultA));
        assertTrue(reg.isFollowing(alice, carol));
        assertFalse(reg.isFollowing(alice, vaultB));
        bool sawA;
        bool sawC;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == vaultA) sawA = true;
            if (list[i] == carol) sawC = true;
        }
        assertTrue(sawA);
        assertTrue(sawC);
    }

    function test_followerCount_multipleFollowers() public {
        vm.prank(alice);
        reg.follow(vaultA);
        vm.prank(bob);
        reg.follow(vaultA);
        vm.prank(carol);
        reg.follow(vaultA);
        assertEq(reg.followerCount(vaultA), 3);
        vm.prank(bob);
        reg.unfollow(vaultA);
        assertEq(reg.followerCount(vaultA), 2);
    }

    function test_follow_emitsEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        reg.follow(vaultA);
        Vm.Log[] memory l = vm.getRecordedLogs();
        assertEq(l.length, 1);
        assertEq(l[0].topics[0], keccak256("Followed(address,address)"));
    }

    function test_unfollow_emitsEvent() public {
        vm.prank(alice);
        reg.follow(vaultA);
        vm.recordLogs();
        vm.prank(alice);
        reg.unfollow(vaultA);
        Vm.Log[] memory l = vm.getRecordedLogs();
        assertEq(l.length, 1);
        assertEq(l[0].topics[0], keccak256("Unfollowed(address,address)"));
    }

    function test_follow_targetCanBeCreatorAddress() public {
        vm.prank(alice);
        reg.follow(bob);
        assertTrue(reg.isFollowing(alice, bob));
        assertEq(reg.followerCount(bob), 1);
    }


    function test_setProfile_storesHandleAndBio() public {
        vm.prank(alice);
        reg.setProfile("alex", "AI & Technology Research");
        (string memory handle, string memory bio) = reg.profileOf(alice);
        assertEq(handle, "alex");
        assertEq(bio, "AI & Technology Research");
        assertEq(reg.ownerOfHandle("alex"), alice);
    }

    function test_setProfile_emitsEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        reg.setProfile("alex", "bio");
        Vm.Log[] memory l = vm.getRecordedLogs();
        assertEq(l.length, 1);
        assertEq(l[0].topics[0], keccak256("ProfileSet(address,string,string)"));
    }

    function test_setProfile_handleTooShortReverts() public {
        vm.prank(alice);
        vm.expectPartialRevert(_sel("InvalidHandleLength()"));
        reg.setProfile("ab", "bio");
    }

    function test_setProfile_handleTooLongReverts() public {
        bytes memory b = new bytes(21);
        for (uint256 i = 0; i < 21; i++) {
            b[i] = "a";
        }
        vm.prank(alice);
        vm.expectPartialRevert(_sel("InvalidHandleLength()"));
        reg.setProfile(string(b), "bio");
    }

    function test_setProfile_handleBoundaryLengthsOk() public {
        bytes memory b20 = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            b20[i] = "a";
        }
        vm.prank(alice);
        reg.setProfile("abc", "bio");
        vm.prank(bob);
        reg.setProfile(string(b20), "bio");
    }

    function test_setProfile_invalidCharsRevert() public {
        vm.startPrank(alice);
        vm.expectPartialRevert(_sel("InvalidHandleChar()"));
        reg.setProfile("Alex", "bio");
        vm.expectPartialRevert(_sel("InvalidHandleChar()"));
        reg.setProfile("al ex", "bio");
        vm.expectPartialRevert(_sel("InvalidHandleChar()"));
        reg.setProfile("al.ex", "bio");
        vm.stopPrank();
    }

    function test_setProfile_allowedCharsOk() public {
        vm.prank(alice);
        reg.setProfile("al-ex_9", "bio");
        (string memory handle,) = reg.profileOf(alice);
        assertEq(handle, "al-ex_9");
    }

    function test_setProfile_bioTooLongReverts() public {
        bytes memory b = new bytes(161);
        for (uint256 i = 0; i < 161; i++) {
            b[i] = "a";
        }
        vm.prank(alice);
        vm.expectPartialRevert(_sel("BioTooLong()"));
        reg.setProfile("alex", string(b));
    }

    function test_setProfile_bioAtLimitOk() public {
        bytes memory b = new bytes(160);
        for (uint256 i = 0; i < 160; i++) {
            b[i] = "a";
        }
        vm.prank(alice);
        reg.setProfile("alex", string(b));
    }

    function test_setProfile_emptyBioOk() public {
        vm.prank(alice);
        reg.setProfile("alex", "");
        (, string memory bio) = reg.profileOf(alice);
        assertEq(bio, "");
    }

    function test_setProfile_duplicateHandleReverts() public {
        vm.prank(alice);
        reg.setProfile("alex", "bio");
        vm.prank(bob);
        vm.expectPartialRevert(_sel("HandleTaken()"));
        reg.setProfile("alex", "other bio");
    }

    function test_setProfile_sameOwnerCanReuseOwnHandle() public {
        vm.startPrank(alice);
        reg.setProfile("alex", "bio one");
        reg.setProfile("alex", "bio two");
        vm.stopPrank();
        (string memory handle, string memory bio) = reg.profileOf(alice);
        assertEq(handle, "alex");
        assertEq(bio, "bio two");
        assertEq(reg.ownerOfHandle("alex"), alice);
    }

    function test_setProfile_changingHandleFreesOldOne() public {
        vm.startPrank(alice);
        reg.setProfile("alex", "bio");
        reg.setProfile("alexander", "bio");
        vm.stopPrank();
        assertEq(reg.ownerOfHandle("alex"), address(0));
        assertEq(reg.ownerOfHandle("alexander"), alice);

        vm.prank(bob);
        reg.setProfile("alex", "bob's bio now");
        assertEq(reg.ownerOfHandle("alex"), bob);
    }

    function test_setProfile_unknownHandleOwnerIsZero() public view {
        assertEq(reg.ownerOfHandle("nobody"), address(0));
    }

    function test_profileOf_defaultIsEmpty() public view {
        (string memory handle, string memory bio) = reg.profileOf(alice);
        assertEq(bytes(handle).length, 0);
        assertEq(bytes(bio).length, 0);
    }
}
