// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NFTCollection} from "../../src/nft/NFTCollection.sol";

contract NftHandler is Test {
    NFTCollection public nft;

    address[] public users;
    uint256 public immutable MAX_SUPPLY;
    // BaseTest mints 3-3 NFTs for 2 users in setUp
    // thus nft contract Eth balance = 0.12 (6 * 0.02 eth per NFT)
    uint256 public expectedTotalSupply;
    uint256 public expectedBalance;

    constructor(
        NFTCollection _nft,
        uint256 _maxSupply,
        address[] memory _users
    ) {
        nft = _nft;
        MAX_SUPPLY = _maxSupply;
        users = _users;
        expectedTotalSupply = 6;
        expectedBalance = 0.12 ether;
    }
    function publicMint(uint256 userSeed, uint256 quantity) external {
        if (quantity == 0) return;

        address user = users[userSeed % users.length];
        uint256 currentBalance = nft.balanceOf(user);
        uint256 maxAllowedNfts = nft.maxMintPerAddress() - currentBalance;

        if (maxAllowedNfts == 0) return;

        uint256 availableSupply = MAX_SUPPLY - expectedTotalSupply;
        if (availableSupply == 0) return;

        uint256 actualMax = maxAllowedNfts < availableSupply
            ? maxAllowedNfts
            : availableSupply;

        quantity = bound(quantity, 1, actualMax);
        uint256 cost = nft.publicMintCost() * quantity;

        vm.deal(user, cost);

        vm.prank(user);
        nft.publicMint{value: cost}(quantity);

        expectedTotalSupply += quantity;
        expectedBalance += cost;
    }

    function reveal() external {
        if (nft.isRevealed()) return;
        
        vm.prank(nft.owner());
        nft.reveal("ipfs://test/");
    }

    function withdraw() external {
        if (expectedBalance == 0) return;

        vm.prank(nft.owner());
        nft.withdraw();

        expectedBalance = 0;
    }

    function forceSendEth(uint256 amount) external {
        amount = bound(amount, 1, 100 ether);
  
        ForceETH attacker = new ForceETH();
        vm.deal(address(attacker), amount);

        attacker.forceSend(address(nft));
    
    }

    function withdrawToRejectingRecipient() external {
        if (expectedBalance == 0) return;

        RejectETH attacker = new RejectETH();

        address originalRecipient = nft.recipient();

        vm.startPrank(nft.owner());
        nft.setRecipient(address(attacker));

        vm.expectRevert(); 
        nft.withdraw();

        nft.setRecipient(originalRecipient);
        vm.stopPrank();
    }
}


contract ForceETH {
    function forceSend(address target) external {
        // "selfdestruct" has been deprecated
        selfdestruct(payable(target));
    }
}

contract RejectETH {
    receive() external payable {
        revert("I don't like ETH!");
    }
}