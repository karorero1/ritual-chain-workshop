// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MerkleBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool finalized;
        address winner;
        bytes32 merkleRoot;
        mapping(address => bool) hasRevealed;
        mapping(address => bytes32) answerHash;
        address[] participants;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool finalized;
        address winner;
        bytes32 merkleRoot;
        uint256 participantCount;
    }

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 reward);
    event AnswerCommitted(uint256 indexed id, address indexed participant, bytes32 hash);
    event AnswerRevealed(uint256 indexed id, address indexed participant);
    event WinnerFinalized(uint256 indexed id, address indexed winner);

    modifier challengeExists(uint256 id) {
        require(challenges[id].owner != address(0), "Challenge does not exist");
        _;
    }

    modifier onlySubmissionPhase(uint256 id) {
        require(block.timestamp <= challenges[id].submissionDeadline, "Submission phase ended");
        _;
    }

    modifier onlyRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].submissionDeadline, "Not reveal phase");
        require(block.timestamp <= challenges[id].revealDeadline, "Reveal phase ended");
        _;
    }

    modifier onlyAfterReveal(uint256 id) {
        require(block.timestamp > challenges[id].revealDeadline, "Reveal phase not over");
        _;
    }

    modifier onlyOwner(uint256 id) {
        require(msg.sender == challenges[id].owner, "Not challenge owner");
        _;
    }

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function createChallenge(
        string calldata prompt,
        uint256 submissionDeadline,
        uint256 revealDuration
    ) external payable {
        require(msg.value > 0, "Reward must be > 0 RIT");
        require(submissionDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.reward = msg.value;
        c.submissionDeadline = submissionDeadline;
        c.revealDeadline = submissionDeadline + revealDuration;

        emit ChallengeCreated(id, msg.sender, msg.value);
    }

    function commitAnswer(
        uint256 id,
        bytes32 answerHash
    ) external 
        challengeExists(id)
        onlySubmissionPhase(id)
    {
        Challenge storage c = challenges[id];
        require(c.answerHash[msg.sender] == 0, "Already committed");

        c.answerHash[msg.sender] = answerHash;
        c.participants.push(msg.sender);

        emit AnswerCommitted(id, msg.sender, answerHash);
    }

    // setMerkleRoot can now be called during reveal phase
    function setMerkleRoot(uint256 id, bytes32 merkleRoot) external 
        challengeExists(id)
        onlyOwner(id)
        onlyRevealPhase(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.merkleRoot == bytes32(0), "Merkle root already set");
        require(c.participants.length > 0, "No participants");

        c.merkleRoot = merkleRoot;
    }

    function revealAndVerify(
        uint256 id,
        string calldata answer,
        bytes32 salt,
        bytes32[] calldata merkleProof
    ) external 
        challengeExists(id)
        onlyRevealPhase(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.answerHash[msg.sender] != 0, "No commitment found");
        require(!c.hasRevealed[msg.sender], "Already revealed");
        require(c.merkleRoot != bytes32(0), "Merkle root not set");

        bytes32 computedHash = keccak256(abi.encodePacked(answer, salt));
        require(computedHash == c.answerHash[msg.sender], "Answer does not match commitment");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, computedHash));
        require(verifyMerkleProof(merkleProof, c.merkleRoot, leaf), "Invalid merkle proof");

        c.hasRevealed[msg.sender] = true;

        emit AnswerRevealed(id, msg.sender);
    }

    function finalizeWinner(uint256 id, address winner) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterReveal(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.merkleRoot != bytes32(0), "Merkle root not set");
        require(c.hasRevealed[winner], "Winner must have revealed");
        require(c.answerHash[winner] != 0, "Winner must have committed");

        c.finalized = true;
        c.winner = winner;

        payable(winner).transfer(c.reward);

        emit WinnerFinalized(id, winner);
    }

    function verifyMerkleProof(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash < proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }
        return computedHash == root;
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            reward: c.reward,
            submissionDeadline: c.submissionDeadline,
            revealDeadline: c.revealDeadline,
            finalized: c.finalized,
            winner: c.winner,
            merkleRoot: c.merkleRoot,
            participantCount: c.participants.length
        });
    }

    function getParticipants(uint256 id) external view returns (address[] memory) {
        return challenges[id].participants;
    }

    function hasRevealed(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasRevealed[participant];
    }

    function getAnswerHash(uint256 id, address participant) external view returns (bytes32) {
        return challenges[id].answerHash[participant];
    }
}
