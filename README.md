# NFTCollection

Gas-efficient NFT contract built with ERC721A.

## ✨ Features

- Whitelist mint (Merkle proof)
- Public mint
- Max supply and per-wallet limits
- Reveal mechanism (hidden → real metadata)
- Royalties (ERC2981)
- Pause control
- Secure ETH withdrawal

---

## 🧱 Tech Stack

- Solidity ^0.8.20  
- ERC721A  
- OpenZeppelin  

---

## ⚙️ How It Works

### Minting

- **Whitelist phase**: only approved addresses can mint using a Merkle proof  
- **Public phase**: open minting for everyone  

Both enforce:
- Correct ETH payment
- Max supply limit
- Per-wallet mint cap  

---

### Reveal

- Before reveal → all tokens return `hiddenURI`  
- After reveal → tokens use `baseURI + tokenId + ".json"`  

---

### Withdraw

- Only owner can withdraw funds  
- ETH is sent to the `recipient` address  

---

## 🔑 Key Variables

| Variable | Description |
|--------|------------|
| `maxSupply` | Maximum NFTs |
| `whitelistMintCost` | Whitelist mint price |
| `publicMintCost` | Public mint price |
| `maxMintPerAddress` | Max NFTs per wallet |
| `merkleRoot` | Whitelist root |
| `recipient` | Withdrawal address |

---

## ▶️ How to Run

### 1. Clone repo

```bash
git clone https://github.com/theonomiMC/NFTCollection.git
cd NFTCollection
```