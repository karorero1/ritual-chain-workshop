# Test Plan – MerkleBounty

- Happy path: 2 participants commit → reveal with proofs → set merkle root → finalize winner
- Cannot reveal before deadline (reverts)
- Cannot reveal without merkle root (reverts)
- Invalid merkle proof (reverts)
