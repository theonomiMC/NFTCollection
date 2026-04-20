# NFTCollection

A Solidity project for an NFT collection and NFT staking system.

This repo currently contains:

- an ERC721A-based NFT collection
- a mintable ERC20 reward token interface/integration
- an NFT staking contract with per-second reward distribution

## Overview

The project started as a gas-efficient NFT collection and was later extended with a staking module.

The staking system is designed so that:

- users stake NFTs into the staking contract
- rewards accrue over time
- rewards are distributed using accumulator-based accounting
- users can claim rewards without iterating over all stakers

## Contracts

### NFTCollection
Gas-efficient ERC721A NFT contract with:

- whitelist mint using Merkle proof
- public mint
- max supply and per-wallet limits
- reveal mechanism
- royalties via ERC2981
- pause control
- secure ETH withdrawal

### NFTStaking
ERC721 staking contract with:

- batch stake and unstake
- per-second reward emissions
- accumulator-based reward accounting
- per-user staked token tracking
- claimable reward settlement
- role-based reward rate updates

## NFT Collection Features

- Whitelist mint
- Public mint
- Max supply cap
- Wallet mint limits
- Hidden metadata before reveal
- Base URI reveal flow
- Royalties
- Pause support
- Withdraw to recipient

## Staking Design

Each staked NFT counts as 1 staking unit.

Rewards are tracked using these core variables:

- `accRewardPerShare`: cumulative reward per staked NFT
- `rewardCheckpoint`: user checkpoint used to avoid double counting
- `pendingRewards`: rewards already earned but not yet claimed
- `balanceOf`: number of NFTs staked by a user
- `totalStaked`: total NFTs staked globally

This design avoids looping over all users and supports multiple stakers efficiently.

## How Staking Works

### Stake
When a user stakes NFTs:

1. the pool is updated
2. the user's rewards are settled under their old balance
3. NFTs are transferred into the staking contract
4. user balance and total staked are updated
5. the user's reward checkpoint is updated

### Unstake
When a user unstakes NFTs:

1. the pool is updated
2. the user's rewards are settled
3. ownership bookkeeping is cleared
4. balances are reduced
5. NFTs are transferred back to the user

### Claim
When a user claims:

1. the pool is updated
2. the user's rewards are settled
3. pending rewards are minted to the user

## Tech Stack

- Solidity ^0.8.24
- ERC721A
- OpenZeppelin
- Foundry

## Project Structure

```bash
src/
  NFTCollection.sol
  NFTStaking.sol
  GovernanceToken.sol
  interfaces/