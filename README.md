# MerkleBounty – Zero-Knowledge Style Verification

This contract uses **merkle tree verification** to enable efficient batch validation of submissions. Instead of storing all answers on-chain, only the merkle root is stored, enabling gas-efficient verification.

## How it works
1. Participants commit to their answers by submitting a hash
2. During reveal phase, participants provide their answer, salt, and merkle proof
3. The contract verifies the answer matches the commitment and the merkle proof
4. Owner sets the merkle root during reveal phase
5. Owner finalizes the winner after reveal phase ends

## Why merkle trees?
Gas-efficient verification, privacy-preserving, and enables efficient batch validation.

## Contract Address (Ritual Testnet)
0xA70F931dFE9Cc1922391a21D9DB788F4489BF7C1

## Network
Ritual Chain Testnet (ID: 1979)

## Native Token
RIT (Ritual Token) – 18 decimals
