# NFT Staking Protocol

A production-oriented Solidity project implementing an NFT collection and a staking-based reward distribution system.

## 📌 Overview

This project consists of three core components:

- **ERC721A NFT Collection**
- **NFT Staking Contract**
- **ERC20 Reward Token**

The system allows users to stake NFTs and earn rewards over time using a gas-efficient accumulator-based model.

---

## 🧱 Contracts

### NFTCollection

Gas-efficient ERC721A-based NFT contract.

**Features:**
- Whitelist mint (Merkle proof)
- Public mint
- Max supply enforcement
- Per-wallet mint limits
- Reveal mechanism (hidden → baseURI + tokenId)
- ERC2981 royalties
- Pause control
- Secure ETH withdrawal

---

### NFTStaking

Core staking contract responsible for reward distribution.

**Features:**
- Stake / unstake NFTs (batch supported)
- Per-second reward emission
- Accumulator-based reward accounting (O(1))
- Per-user staking tracking
- Claimable rewards
- Role-based reward rate updates

---

### GovernanceToken

ERC20 reward token with:
- capped max supply
- role-based minting (`MINTER_ROLE`)
- mint controlled by staking contract

---

## ⚙️ Reward Model

Rewards are distributed using a cumulative index:

- `accRewardPerShare` → total rewards per staked NFT
- `rewardCheckpoint` → user-specific accounting checkpoint
- `pendingRewards` → stored rewards not yet claimed

Core formula:
```
earned = pendingRewards + (balance * accRewardPerShare - rewardCheckpoint)
```


This design:
- avoids looping over users
- scales efficiently with many stakers
- mirrors patterns used in production DeFi systems

---

## 🔄 Staking Lifecycle

### Stake

1. update pool state
2. settle user rewards
3. transfer NFTs to contract
4. update balances
5. update reward checkpoint

---

### Unstake

1. update pool
2. settle rewards
3. update balances
4. transfer NFTs back to user

---

### Claim

1. update pool
2. settle rewards
3. mint ERC20 rewards to user

---

## 🧪 Testing

### Unit Tests

Covers:

- NFT minting, limits, and pricing
- whitelist logic
- staking flows (stake / unstake / claim)
- reward distribution correctness
- access control and failure cases

---

### Invariant Testing

The system is tested under randomized sequences of actions.

#### NFTCollection invariants:

- `totalSupply` consistency
- user balances never exceed wallet limits
- ETH accounting (including forced ETH scenarios)
- tokenURI correctness before and after reveal

#### NFTStaking invariants:

- `totalStaked == sum(balanceOf(users))`
- mapping ↔ array consistency
- NFT custody correctness
- no duplicate tokens per user
- reward accounting correctness

---

## 📊 Coverage

| Contract            | Coverage |
|-------------------|---------|
| NFTCollection      | 100%    |
| GovernanceToken    | 100%    |
| NFTStaking         | ~99% lines / ~94% branches |

---

## 🔒 Security Considerations

- Reentrancy protection (`ReentrancyGuard`)
- Direct NFT transfer attack prevented (`operator` check in `onERC721Received`)
- Safe reward accounting (no double counting)
- Role-based access control (`AccessControl`)
- ETH withdrawal handles unexpected ETH transfers
- Failure handling for rejecting recipients

---

## 🧠 Design Notes

- Each NFT represents 1 staking unit
- Reward distribution is time-based (`rewardPerSecond`)
- System avoids loops over users (gas-efficient)
- Uses patterns similar to MasterChef-style contracts

---

## 📁 Project Structure
```
src/
  nft/
    NFTCollection.sol
  staking/
    NFTStaking.sol
  token/
    GovernanceToken.sol
  interfaces/
```

## 🚀 How to Run

```bash
git clone https://github.com/theonomiMC/NFTCollection.git
cd NFTCollection

forge install
forge build
forge test
forge coverage
```

## 🔮 Future Improvements
- Multisig admin control
- Emergency withdraw for staking
- Batch size limits (gas protection)
- Integration tests (NFT ↔ staking ↔ rewards)
- Frontend integration