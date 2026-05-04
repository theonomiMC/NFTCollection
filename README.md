# NFT Staking Protocol
![Foundry](https://img.shields.io/badge/Built_with-Foundry-FF8000.svg?style=flat-square)
![Coverage](https://img.shields.io/badge/Coverage-98%25-brightgreen.svg?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)


## 🟢 Live Testnet Deployments (Sepolia)

A production-oriented Solidity project implementing an NFT collection and a staking-based reward distribution system.

*   **NFTCollection:** [`0xEE2BC4Bea4F5193EB12947a5E4F7CC9D3d26fdBf`](https://sepolia.etherscan.io/address/0xEE2BC4Bea4F5193EB12947a5E4F7CC9D3d26fdBf#code)
*   **GovernanceToken:** [`0xad6D988db1F9b695276080BF24D95CB2F7A8c7EA`](https://sepolia.etherscan.io/address/0xad6D988db1F9b695276080BF24D95CB2F7A8c7EA#code)
*   **NFTStaking:** [`0x99b8522Fd6c282f34E5B5af57B18044C88d12c37`](https://sepolia.etherscan.io/address/0x99b8522Fd6c282f34E5B5af57B18044C88d12c37#code)


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
earned = pendingRewards + ((balance * accRewardPerShare) / PRECISION - rewardCheckpoint)
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
- Whitelist logic
- Staking flows (stake / unstake / claim)
- Reward distribution correctness
- Access control and failure cases

---

### Invariant Testing

The system is tested under randomized sequences of actions to ensure state consistency.

#### NFTCollection invariants:

- `totalSupply` consistency
- User balances never exceed wallet limits
- ETH accounting (including forced ETH scenarios)
- `tokenURI` correctness before and after reveal

#### NFTStaking invariants:

- `totalStaked == sum(balanceOf(users))`
- Mapping ↔ array consistency
- NFT custody correctness
- No duplicate tokens per user
- Reward accounting correctness

## Additional Testing

- Reentrancy tested using a malicious ERC721 mock
- Callback attacks during `safeTransferFrom` are prevented

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
- Production admin model designed around multisig ownership/control
- ETH withdrawal handles unexpected ETH transfers
- Failure handling for rejecting recipients

---

## 🔐 Production Admin Model

Privileged roles are designed to be controlled by a multisig wallet in production.

Recommended setup:

- `NFTCollection` owner → multisig
- `GovernanceToken` `DEFAULT_ADMIN_ROLE` → multisig
- `GovernanceToken` `MINTER_ROLE` → `NFTStaking`
- `NFTStaking` `DEFAULT_ADMIN_ROLE` → multisig
- `NFTStaking` `REWARD_MANAGER_ROLE` → multisig

User actions remain permissionless:

- `stake`
- `unstake`
- `claim`

This keeps user interactions immediate while admin actions require multisig approval.

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
---
### Deployment Notes

- Contracts are verified on Etherscan
- Admin roles are intended to be transferred to a multisig wallet
- Current deployment may still be controlled by a deployer EOA

---
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
- Integration tests (NFT ↔ staking ↔ rewards)
- Frontend integration