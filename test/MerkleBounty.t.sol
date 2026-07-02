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

    // Helper to compute merkle root from leaves (matches contract's verifyMerkleProof)
    function computeMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        if (leaves.length == 1) return leaves[0];
        
        bytes32[] memory newLeaves = new bytes32[]((leaves.length + 1) / 2);
        for (uint i = 0; i < newLeaves.length; i++) {
            if (i * 2 + 1 < leaves.length) {
                // Sort the pair before hashing (matches contract's ordering)
                bytes32 left = leaves[i * 2];
                bytes32 right = leaves[i * 2 + 1];
                if (left < right) {
                    newLeaves[i] = keccak256(abi.encodePacked(left, right));
                } else {
                    newLeaves[i] = keccak256(abi.encodePacked(right, left));
                }
            } else {
                newLeaves[i] = leaves[i * 2];
            }
        }
        return computeMerkleRoot(newLeaves);
    }

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);

        aliceHash = keccak256(abi.encodePacked(aliceAnswer, aliceSalt));
        bobHash = keccak256(abi.encodePacked(bobAnswer, bobSalt));

        // Build merkle tree leaves
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(alice, aliceHash));
        leaves[1] = keccak256(abi.encodePacked(bob, bobHash));

        // Sort leaves before building root (matches contract ordering)
        if (leaves[0] < leaves[1]) {
            merkleRoot = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        } else {
            merkleRoot = keccak256(abi.encodePacked(leaves[1], leaves[0]));
        }

        // Build proofs: for alice, proof is the sibling leaf (leaves[1])
        aliceProof = new bytes32[](1);
        aliceProof[0] = leaves[1];

        // For bob, proof is the sibling leaf (leaves[0])
        bobProof = new bytes32[](1);
        bobProof[0] = leaves[0];

        bounty = new MerkleBounty();
        vm.startPrank(owner);
        uint256 submissionDeadline = block.timestamp + 1 days;
        bounty.createChallenge{value: reward}("Test", submissionDeadline, 2 days);
        challengeId = 0;
        vm.stopPrank();
    }

    function testFullFlow() public {
        // 1. Commit answers
        vm.startPrank(alice);
        bounty.commitAnswer(challengeId, aliceHash);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.commitAnswer(challengeId, bobHash);
        vm.stopPrank();

        // 2. Move to reveal phase
        vm.warp(block.timestamp + 1 days + 1);
        
        // 3. Set merkle root
        vm.startPrank(owner);
        bounty.setMerkleRoot(challengeId, merkleRoot);
        vm.stopPrank();

        // 4. Reveal with proofs
        vm.startPrank(alice);
        bounty.revealAndVerify(challengeId, aliceAnswer, aliceSalt, aliceProof);
        vm.stopPrank();

        vm.startPrank(bob);
        bounty.revealAndVerify(challengeId, bobAnswer, bobSalt, bobProof);
        vm.stopPrank();

        // 5. Move to after reveal phase
        vm.warp(block.timestamp + 2 days + 1);

        // 6. Finalize winner
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
}
