// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    IERC721Metadata
} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BaseTest} from "./base/BaseTest.t.sol";
import {
    NFTCollection,
    InvalidAddress,
    InvalidURI,
    MintNotActive,
    InvalidAmount,
    InsufficientSupply,
    MintLimitExceeded,
    InvalidMerkleProof,
    TransferFailed,
    AlreadyRevealed,
    RoyaltyTooHigh,
    TokenNotExists
} from "../src/nft/NFTCollection.sol";

contract NFTCollectionTest is BaseTest {
    function test_InitialStates() public view {
        assertEq(nft.owner(), admin);

        assertEq(nft.name(), "MyNFT");
        assertEq(nft.symbol(), "MNFT");

        assertEq(nft.whitelistMintCost(), 0.01 ether);
        assertEq(nft.publicMintCost(), 0.02 ether);
        assertEq(nft.maxMintPerAddress(), 10);

        assertEq(nft.hiddenURI(), "ipfs://hidden.json");
        assertEq(nft.recipient(), admin);

        assertEq(nft.isRevealed(), false);
    }
    // Constructor Reverts
    function test_Constructor_NoInitOwner_Reverts() public {
        vm.prank(admin);
        vm.expectRevert();
        new NFTCollection(
            address(0),
            "MyNFT",
            "MNFT",
            MAX_SUPPLY,
            0.01 ether,
            0.02 ether,
            10,
            "ipfs://hidden.json",
            admin,
            500
        );
    }

    function test_Constructor_NoRecipient_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(InvalidAddress.selector);
        new NFTCollection(
            admin,
            "MyNFT",
            "MNFT",
            MAX_SUPPLY,
            0.01 ether,
            0.02 ether,
            10,
            "ipfs://hidden.json",
            address(0),
            500
        );
    }

    function test_Constructor_NoHiddenUri_Reverts() public {
        vm.expectRevert(InvalidURI.selector);
        new NFTCollection(
            admin,
            "MyNFT",
            "MNFT",
            MAX_SUPPLY,
            0.01 ether,
            0.02 ether,
            10,
            "",
            admin,
            500
        );
    }

    function test_Constructor_ZeroMaxMintAmount_Reverts() public {
        vm.expectRevert(InvalidAmount.selector);
        new NFTCollection(
            admin,
            "MyNFT",
            "MNFT",
            MAX_SUPPLY,
            0.01 ether,
            0.02 ether,
            0,
            "ipfs://hidden.json",
            admin,
            500
        );
    }

    function test_Constructor_RoyaltyTooHigh_Reverts() public {
        vm.expectRevert(RoyaltyTooHigh.selector);

        new NFTCollection(
            admin,
            "MyNFT",
            "MNFT",
            MAX_SUPPLY,
            0.01 ether,
            0.02 ether,
            10,
            "ipfs://hidden.json",
            admin,
            1001
        );
    }

    function test_Constructor_ZeroMaxSupply_Reverts() public {
        vm.expectRevert(InvalidAmount.selector);
        new NFTCollection(
            admin,
            "MyNFT",
            "MNFT",
            0,
            0.01 ether,
            0.02 ether,
            10,
            "ipfs://hidden.json",
            admin,
            500
        );
    }
    // Mint
    function test_NFTMint_AssignsOwnership() public {
        uint256 balanceBefore = nft.balanceOf(toko);
        uint256 totalSupplyBefore = nft.totalSupply();

        vm.deal(toko, 1 ether);

        vm.prank(toko);
        nft.publicMint{value: 0.02 ether}(1);

        uint256 expectedTokenId = totalSupplyBefore + 1;

        assertEq(nft.ownerOf(expectedTokenId), toko);
        assertEq(nft.balanceOf(toko), balanceBefore + 1);
        assertEq(nft.totalSupply(), totalSupplyBefore + 1);
    }

    function test_PublicMint_NotActive_Reverts() public {
        vm.prank(admin);
        nft.setPublicMintActive(false);

        vm.deal(toko, 1 ether);

        vm.prank(toko);
        vm.expectRevert(MintNotActive.selector);
        nft.publicMint{value: 0.02 ether}(1);
    }
    // Mint Reverts
    function test_PublicMint_ZeroAmount_Reverts() public {
        vm.deal(toko, 1 ether);

        vm.prank(toko);
        vm.expectRevert(InvalidAmount.selector);
        nft.publicMint{value: 0}(1);
    }

    function test_PublicMint_ZeroQuantity_Reverts() public {
        vm.deal(toko, 1 ether);

        vm.prank(toko);
        vm.expectRevert(InvalidAmount.selector);
        nft.publicMint{value: 0.02 ether}(0);
    }

    function test_PublicMint_ExceedsWalletLimitAcrossMultipleMints() public {
        vm.deal(toko, 1 ether);

        // he has already 3 nfts minted, max allowed mint number = 10
        vm.prank(toko);
        vm.expectRevert(MintLimitExceeded.selector);
        nft.publicMint{value: 0.02 ether * 8}(8);
    }

    function test_PublicMint_WrongPayment_Reverts() public {
        vm.deal(toko, 0.5 ether);

        vm.prank(toko);
        vm.expectRevert(InvalidAmount.selector);
        nft.publicMint{value: 0.001 ether}(1);
    }

    function test_OnMintLimitExceeds_Reverts() public {
        vm.deal(toko, 5 ether);

        vm.prank(toko);
        vm.expectRevert(MintLimitExceeded.selector);
        nft.publicMint{value: 0.02 ether * 11}(11);
    }

    function test_OnInsufficientSupply_Reverts() public {
        vm.deal(toko, 22 ether);

        vm.prank(toko);
        vm.expectRevert(InsufficientSupply.selector);
        nft.publicMint{value: 0.02 ether * (MAX_SUPPLY + 1)}(MAX_SUPPLY + 1);
    }
    // Whitelist mint
    function test_WhitelistMint_ValidProof_Succeeds() public {
        bytes32 leafToko = keccak256(abi.encodePacked(toko));
        bytes32 leafNoa = keccak256(abi.encodePacked(noa));

        bytes32 root = leafToko < leafNoa
            ? keccak256(abi.encodePacked(leafToko, leafNoa))
            : keccak256(abi.encodePacked(leafNoa, leafToko));

        vm.startPrank(admin);
        nft.setMerkleRoot(root);
        nft.setWhitelistActive(true);
        vm.stopPrank();

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leafNoa;

        vm.deal(toko, 1 ether);

        uint256 balanceBefore = nft.balanceOf(toko);

        vm.prank(toko);
        nft.whitelistMint{value: 0.01 ether}(1, proof);

        assertEq(nft.balanceOf(toko), balanceBefore + 1);
    }

    function test_WhitelistMint_NotActive_Reverts() public {
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.deal(toko, 1 ether);
        vm.prank(toko);

        vm.expectRevert(MintNotActive.selector);
        nft.whitelistMint{value: 0.01 ether}(1, emptyProof);
    }

    function test_WhitelistMint_InvalidProof_Reverts() public {
        bytes32 leafToko = keccak256(abi.encodePacked(toko));

        vm.startPrank(admin);
        nft.setMerkleRoot(leafToko);
        nft.setWhitelistActive(true);
        vm.stopPrank();

        bytes32[] memory invalidProof = new bytes32[](0);

        vm.deal(noa, 1 ether);
        vm.prank(noa);

        vm.expectRevert(InvalidMerkleProof.selector);
        nft.whitelistMint{value: 0.01 ether}(1, invalidProof);
    }

    // ADMIN
    function test_Withdraw_AsAdmin_Succeeds() public {
        uint256 adminBalanceBefore = admin.balance;

        vm.deal(toko, 1 ether);
        vm.prank(toko);
        nft.publicMint{value: 0.02 ether * 2}(2);

        uint256 revenue = address(nft).balance;

        vm.prank(admin);
        nft.withdraw();

        assertEq(address(nft).balance, 0);
        assertEq(admin.balance, adminBalanceBefore + revenue);
    }

    function test_SetPublicMintActive_AsAdmin() public {
        // it is active on basetest setup
        assertTrue(nft.publicMintActive());

        vm.prank(admin);
        nft.setPublicMintActive(false);

        assertFalse(nft.publicMintActive());
    }

    function test_SetWhitelistActive_AsAdmin() public {
        assertFalse(nft.whitelistActive());

        vm.prank(admin);
        nft.setWhitelistActive(true);

        assertTrue(nft.whitelistActive());
    }

    function test_SetMerkleRoot_AsAdmin_UpdatesState() public {
        bytes32 newRoot = bytes32(uint256(1234));

        vm.prank(admin);
        nft.setMerkleRoot(newRoot);

        assertEq(nft.merkleRoot(), newRoot);
    }

    function test_Reveal_AsAdmin_UpdatesStateAndURI() public {
        string memory newBaseUri = "ipfs://revealed/";

        vm.prank(admin);
        nft.reveal(newBaseUri);
        // minted to Toko in BaseTest's setUp
        uint256 tokenId = 1;

        assertTrue(nft.isRevealed());
        assertEq(nft.tokenURI(tokenId), "ipfs://revealed/1.json");
    }

    function test_setRecipient_AsAdmin() public {
        address newRecipient = makeAddr("new Recipient");

        assertEq(nft.recipient(), admin);

        vm.prank(admin);
        nft.setRecipient(newRecipient);

        assertEq(nft.recipient(), newRecipient);
    }

    // Non-Admin Reverts
    function test_Withdraw_AsNonAdmin_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        nft.withdraw();
    }

    function test_SetPublicMintActive_AsNotAdmin_Reverts() public {
        // it is active on basetest setup
        assertTrue(nft.publicMintActive());

        vm.prank(toko);
        vm.expectRevert();
        nft.setPublicMintActive(false);
    }

    function test_SetWhitelistActive_AsNotAdmin_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        nft.setWhitelistActive(true);
    }

    function test_SetMerkleRoot_AsNotAdmin_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        nft.setMerkleRoot(bytes32(uint256(1)));
    }

    function test_Reveal_NotAdmin_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        nft.reveal("ipfs://revealed/");
    }

    function test_setRecipient_AsNotAdmin_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        nft.setRecipient(makeAddr("New Recipient"));
    }

    // Reveal / TokenUri
    function test_Reveal_AlreadyRevealed_Reverts() public {
        string memory newBaseUri = "ipfs://revealed/";

        vm.prank(admin);
        nft.reveal(newBaseUri);

        vm.prank(admin);
        vm.expectRevert(AlreadyRevealed.selector);
        nft.reveal("ipfs://another/");
    }

    function test_EmptyBaseUri_Reveal_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(InvalidURI.selector);
        nft.reveal("");
    }

    function test_setRecipient_EmptyAddress_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(InvalidAddress.selector);
        nft.setRecipient(address(0));
    }

    function test_TokenURI_BeforeReveal_ReturnsHiddenURI() public {
        uint256 tokenId = 1;

        assertFalse(nft.isRevealed());
        assertEq(nft.tokenURI(tokenId), nft.hiddenURI());
    }
    function test_TokenURI_OnNonExistingTokenId_Reverts() public {
        uint256 tokenId = 111;
        vm.expectRevert(TokenNotExists.selector);
        nft.tokenURI(tokenId);
    }
    // PAUSE
    function test_PublicMint_Reverts_WhenPaused() public {
        vm.prank(admin);
        nft.pause();

        vm.deal(toko, 1 ether);

        vm.prank(toko);
        vm.expectRevert();
        nft.publicMint{value: 0.02 ether}(1);
    }

    function test_Pause_AsNonAdmin_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        nft.pause();
    }
    function test_Unpause_AsAdmin_Succeeds() public {
        vm.startPrank(admin);
        nft.pause();
        nft.unpause(); // The missing function!
        vm.stopPrank();

        // Verify we can successfully mint again after unpausing
        vm.deal(toko, 1 ether);
        vm.prank(admin);
        nft.setPublicMintActive(true);

        vm.prank(toko);
        nft.publicMint{value: 0.02 ether}(1);

        // If the mint succeeds, unpause worked
        assertTrue(nft.balanceOf(toko) > 0);
    }

    function test_Unpause_AsNonAdmin_Reverts() public {
        vm.prank(admin);
        nft.pause();

        vm.prank(toko);
        vm.expectRevert(); // Expect standard Ownable revert
        nft.unpause();
    }
    // RoyaltiInfo
    function test_RoyaltyInfo_ReturnsCorrectRecipientAndAmount() public view {
        uint256 tokenId = 1;
        uint256 salePrice = 1 ether;

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            salePrice
        );

        assertEq(receiver, admin);
        assertEq(royaltyAmount, 0.05 ether);
    }
    function test_Constructor_RoyaltyExactlyMax_Succeeds() public {
        vm.prank(admin);

        new NFTCollection(
            admin,
            "MyNFT",
            "MNFT",
            MAX_SUPPLY,
            0.01 ether,
            0.02 ether,
            10,
            "ipfs://hidden.json",
            admin,
            1000
        );
    }
    // View Functions
    function test_getTotalMinted() public view {
        assertEq(nft.totalMinted(), nft.totalSupply());
    }

    function test_SupportsInterface() public view {
        // ERC721
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));

        // ERC721 Metadata (name, symbol, tokenURI)
        assertTrue(nft.supportsInterface(type(IERC721Metadata).interfaceId));

        // ERC2981 (royalties)
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));

        // IERC165 (base interface detection)
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));

        // Random interface (should NOT be supported)
        assertFalse(nft.supportsInterface(bytes4(0x12345678)));
    }

    function test_TransferFail_Reverts() public {
        BadReceiver badContract = new BadReceiver();

        vm.startPrank(admin);
        nft.setRecipient(address(badContract));
        vm.expectRevert(TransferFailed.selector);
        nft.withdraw();
        vm.stopPrank();
    }
}

contract BadReceiver {
    receive() external payable {
        revert();
    }
}
