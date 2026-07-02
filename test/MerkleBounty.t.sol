// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../src/MerkleBounty.sol";

contract MerkleBountyTest is Test {
    MerkleBounty public bounty;
    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    uint256 challengeId;
    uint256 reward = 1 ether;

    bytes32 aliceHash;
    bytes32 bobHash;
    bytes32 aliceSalt = keccak256("alice_salt");
    bytes32 bobSalt = keccak256("bob_salt");
    string aliceAnswer = "Alice's solution";
    string bobAnswer = "Bob's solution";

    bytes32 merkleRoot;
    bytes32[] aliceProof;
    bytes32[] bobProof;

    // Simple merkle proof verification for 2 leaves
    function buildMerkleProof() internal {
        // Compute leaves
        bytes32 leaf1 = keccak256(abi.encodePacked(alice, aliceHash));
        bytes32 leaf2 = keccak256(abi.encodePacked(bob, bobHash));
        
        // Sort leaves (needed for consistent hashing)
        bytes32[2] memory sortedLeaves;
        if (leaf1 < leaf2) {
            sortedLeaves[0] = leaf1;
            sortedLeaves[1] = leaf2;
        } else {
            sortedLeaves[0] = leaf2;
            sortedLeaves[1] = leaf1;
        }
        
        // Compute root
        merkleRoot = keccak256(abi.encodePacked(sortedLeaves[0], sortedLeaves[1]));
        
        // Build proofs - each proof contains the sibling leaf
        aliceProof = new bytes32[](1);
        bobProof = new bytes32[](1);
        
        if (leaf1 < leaf2) {
            // Alice's proof is leaf2, Bob's proof is leaf1
            aliceProof[0] = leaf2;
            bobProof[0] = leaf1;
        } else {
            // Alice's proof is leaf2, Bob's proof is leaf1 (swapped)
            aliceProof[0] = leaf2;
            bobProof[0] = leaf1;
        }
    }

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        aliceHash = keccak256(abi.encodePacked(aliceAnswer, aliceSalt));
        bobHash = keccak256(abi.encodePacked(bobAnswer, bobSalt));

        buildMerkleProof();

        bounty = new MerkleBounty();
        vm.startPrank(owner);
        uint256 commitDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", commitDeadline, 2 days);
        challengeId = 0;
        vm.stopPrank();
    }

    function testFullFlow() public {
        // Commit
        vm.startPrank(alice);
        bounty.commitAnswer(challengeId, aliceHash);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.commitAnswer(challengeId, bobHash);
        vm.stopPrank();

        // Move to reveal phase
        vm.warp(block.timestamp + 1 days + 1);

        // Set merkle root
        vm.startPrank(owner);
        bounty.setMerkleRoot(challengeId, merkleRoot);
        vm.stopPrank();

        // Reveal with proofs
        vm.startPrank(alice);
        bounty.revealAndVerify(challengeId, aliceAnswer, aliceSalt, aliceProof);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAndVerify(challengeId, bobAnswer, bobSalt, bobProof);
        vm.stopPrank();

        // Move to after reveal phase
        vm.warp(block.timestamp + 2 days + 1);

        // Finalize winner
        vm.startPrank(owner);
        bounty.finalizeWinner(challengeId, bob);
        vm.stopPrank();

        MerkleBounty.ChallengeInfo memory info = bounty.getChallengeInfo(challengeId);
        assertTrue(info.finalized);
        assertEq(info.winner, bob);
        assertEq(bob.balance, 1 ether + reward);
    }

    function testCannotRevealBeforeDeadline() public {
        vm.startPrank(alice);
        bounty.commitAnswer(challengeId, aliceHash);
        vm.warp(block.timestamp + 12 hours);
        vm.expectRevert("Not reveal phase");
        bounty.revealAndVerify(challengeId, aliceAnswer, aliceSalt, aliceProof);
        vm.stopPrank();
    }

    function testCannotRevealWithoutMerkleRoot() public {
        vm.startPrank(alice);
        bounty.commitAnswer(challengeId, aliceHash);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        
        vm.startPrank(alice);
        vm.expectRevert("Merkle root not set");
        bounty.revealAndVerify(challengeId, aliceAnswer, aliceSalt, aliceProof);
        vm.stopPrank();
    }

    function testInvalidMerkleProof() public {
        vm.startPrank(alice);
        bounty.commitAnswer(challengeId, aliceHash);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);

        vm.startPrank(owner);
        bounty.setMerkleRoot(challengeId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(alice);
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256(abi.encodePacked("invalid"));

        vm.expectRevert("Invalid merkle proof");
        bounty.revealAndVerify(challengeId, aliceAnswer, aliceSalt, invalidProof);
        vm.stopPrank();
    }

    function testOnlyOwnerCanFinalize() public {
        vm.startPrank(alice);
        bounty.commitAnswer(challengeId, aliceHash);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.startPrank(owner);
        bounty.setMerkleRoot(challengeId, merkleRoot);
        vm.stopPrank();

        vm.startPrank(alice);
        bounty.revealAndVerify(challengeId, aliceAnswer, aliceSalt, aliceProof);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days + 1);
        vm.startPrank(alice);
        vm.expectRevert("Not challenge owner");
        bounty.finalizeWinner(challengeId, alice);
        vm.stopPrank();
    }
}
