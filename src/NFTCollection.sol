// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "erc721a/ERC721A.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title NFTCollection
/// @author teonomiMC - Natalia Bakakuri
/// @notice ERC721A NFT collection with whitelist + public mint and royalties
/// @dev Uses ERC721A for gas-efficient batch minting and ERC2981 for royalties
contract NFTCollection is ERC721A, ERC2981, Ownable, Pausable, ReentrancyGuard {
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Maximum number of NFTs that can ever be minted
    uint256 private immutable maxSupply;
    /// @notice Price per NFT during whitelist mint
    uint256 public immutable whitelistMintCost;
    /// @notice Price per NFT during public mint
    uint256 public immutable publicMintCost;
    /// @notice Max NFTs a single wallet can mint (across all phases)
    uint256 public immutable maxMintPerAddress;

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Merkle root used to verify whitelist addresses
    bytes32 public merkleRoot;
    /// @notice URI returned before reveal
    string public hiddenURI;
    /// @dev Base URI for revealed tokens
    string private _baseTokenURI;

    /// @notice Whether metadata is revealed
    bool public isRevealed = false;
    /// @notice Whether whitelist mint is active
    bool public whitelistActive;
    /// @notice Whether public mint is active
    bool public publicMintActive;
    /// @notice Address that receives withdrawn funds
    address public recipient;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when public mint occurs
    /// @param to Address receiving NFTs
    /// @param quantity Number of NFTs minted
    event Minted(address indexed to, uint256 quantity);
    /// @notice Emitted when whitelist mint occurs
    /// @param minter Address performing mint
    /// @param quantity Number of NFTs minted
    event WhitelistMinted(address indexed minter, uint256 quantity);
    /// @notice Emitted when merkle root is updated
    /// @param newRoot New merkle root
    event MerkleRootUpdated(bytes32 indexed newRoot);
    /// @notice Emitted when recipient is updated
    /// @param newRecipient New withdrawal address
    event RecipientUpdated(address indexed newRecipient);

    /*//////////////////////////////////////////////////////////////
                             CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    /// @notice Thrown when zero address is used
    error InvalidAddress();
    /// @notice Thrown when URI is empty
    error InvalidURI();
    /// @notice Thrown when mint phase is not active
    error MintNotActive();
    /// @notice Thrown when incorrect ETH amount is sent or invalid quantity
    error InvalidAmount();
    /// @notice Thrown when mint exceeds max supply
    error InsufficientSupply();
    /// @notice Thrown when wallet exceeds mint limit
    error MintLimitExceeded();
    /// @notice Thrown when merkle proof is invalid
    error InvalidMerkleProof();
    /// @notice Thrown when ETH transfer fails
    error TransferFailed();
    /// @notice Thrown if reveal is attempted more than once
    error AlreadyRevealed();
    /// @notice Thrown if royalty fee is too high
    error RoyaltyTooHigh();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the NFT collection
    /// @param _name Collection name
    /// @param _symbol Collection symbol
    /// @param _maxSupply Maximum number of NFTs
    /// @param _whitelistPrice Price per NFT in whitelist phase
    /// @param _publicPrice Price per NFT in public phase
    /// @param _maxMint Max NFTs per wallet
    /// @param _hiddenURI Placeholder metadata URI before reveal
    /// @param _royaltyRecipient Address receiving royalties and withdrawals
    /// @param _royaltyFee Royalty fee in basis points (e.g., 500 = 5%)
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _whitelistPrice,
        uint256 _publicPrice,
        uint256 _maxMint,
        string memory _hiddenURI,
        address _royaltyRecipient,
        uint96 _royaltyFee // e.g., 500 for 5%
    ) ERC721A(_name, _symbol) Ownable(msg.sender) {
        if (_royaltyRecipient == address(0)) revert InvalidAddress();
        if (_royaltyFee > 1000) revert RoyaltyTooHigh();
        if (_maxSupply == 0) revert InvalidAmount();
        if (bytes(_hiddenURI).length == 0) revert InvalidURI();
        if (_maxMint == 0) revert InvalidAmount();

        maxSupply = _maxSupply;
        whitelistMintCost = _whitelistPrice;
        publicMintCost = _publicPrice;
        maxMintPerAddress = _maxMint;
        hiddenURI = _hiddenURI;
        recipient = _royaltyRecipient;

        _setDefaultRoyalty(_royaltyRecipient, _royaltyFee);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN: PAUSE CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause minting and transfers
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/
    /// @dev Verifies whitelist membership using merkle proof
    /// @param user Address to verify
    /// @param proof Merkle proof
    /// @custom:reverts InvalidMerkleProof if proof is invalid
    function _verifyWhitelist(address _user, bytes32[] calldata _proof) internal view {
        bytes32 leaf = keccak256(abi.encodePacked(_user));
        if (!MerkleProof.verify(_proof, merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }
    }

    /// @dev Shared mint logic used by whitelist and public mint
    /// @param to Recipient address
    /// @param quantity Number of NFTs to mint
    /// @param cost Price per NFT
    /// @custom:reverts InvalidAmount if quantity is zero or ETH is incorrect
    /// @custom:reverts InsufficientSupply if max supply exceeded
    /// @custom:reverts MintLimitExceeded if wallet limit exceeded
    function _mintInternal(address to, uint256 _quantity, uint256 _cost) internal {
        if (_quantity == 0) revert InvalidAmount();
        if (msg.value != _quantity * _cost) revert InvalidAmount();

        uint256 supply = totalSupply();
        unchecked {
            if (supply + _quantity > maxSupply) revert InsufficientSupply();
        }

        uint256 minted = _numberMinted(to);
        if (minted + _quantity > maxMintPerAddress) {
            revert MintLimitExceeded();
        }
        _safeMint(to, _quantity);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Mint NFTs during whitelist phase
    /// @param quantity Number of NFTs to mint
    /// @param proof Merkle proof proving whitelist inclusion
    function whitelistMint(uint256 quantity, bytes32[] calldata proof) external payable whenNotPaused nonReentrant {
        if (!whitelistActive) revert MintNotActive();
        _verifyWhitelist(msg.sender, proof);
        _mintInternal(msg.sender, quantity, whitelistMintCost);

        emit WhitelistMinted(msg.sender, quantity);
    }

    /// @notice Mint NFTs during public sale
    /// @param quantity Number of NFTs to mint
    function publicMint(uint256 quantity) external payable whenNotPaused nonReentrant {
        if (!publicMintActive) revert MintNotActive();
        _mintInternal(msg.sender, quantity, publicMintCost);

        emit Minted(msg.sender, quantity);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set new merkle root for whitelist
    /// @param root New merkle root
    function setMerkleRoot(bytes32 _root) external onlyOwner {
        merkleRoot = _root;
        emit MerkleRootUpdated(_root);
    }

    /// @notice Set withdrawal recipient
    /// @param newRecipient Address receiving funds
    function setRecipient(address _newRecipient) external onlyOwner {
        if (_newRecipient == address(0)) revert InvalidAddress();
        recipient = _newRecipient;
        emit RecipientUpdated(_newRecipient);
    }

    /// @notice Enable or disable whitelist mint
    function setWhitelistActive(bool active) external onlyOwner {
        whitelistActive = active;
    }

    /// @notice Enable or disable public mint
    function setPublicMintActive(bool active) external onlyOwner {
        publicMintActive = active;
    }

    /// @notice Reveal NFT metadata
    /// @param baseURI Base URI for revealed tokens
    function reveal(string calldata baseURI) external onlyOwner {
        if (isRevealed) revert AlreadyRevealed();
        if (bytes(baseURI).length == 0) revert InvalidURI();
        _baseTokenURI = baseURI;
        isRevealed = true;
    }

    /// @notice Withdraw all ETH to recipient
    function withdraw() external onlyOwner {
        (bool success,) = payable(recipient).call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    /*//////////////////////////////////////////////////////////////
                        METADATA
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns metadata URI for a token
    /// @param tokenId Token ID
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert("URIQueryForNonexistentToken");

        if (!isRevealed) return hiddenURI;

        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    /*//////////////////////////////////////////////////////////////
                        ERC721A OVERRIDES
    //////////////////////////////////////////////////////////////*/
    /// @dev Token IDs start at 1 instead of 0
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /// @dev Supports ERC165 interface detection
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721A, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Returns total number of minted tokens
    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }
}
