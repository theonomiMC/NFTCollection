// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTCollection} from "../../src/nft/NFTCollection.sol";
import {GovernanceToken} from "../../src/token/GovernanceToken.sol";
import {NFTStaking} from "../../src/staking/NFTStaking.sol";

contract BaseTest is Test {
    NFTCollection internal nft;
    GovernanceToken internal rewardToken;
    NFTStaking internal staking;

    address internal admin;
    address internal toko;
    address internal noa;

    uint256 internal constant REWARD_RATE = 10;
    uint256 internal constant MAX_SUPPLY = 1000;
    uint256 internal constant GOV_MAX_SUPPLY = 1_000_000 ether;

    function setUp() public virtual {
        admin = makeAddr("admin");
        toko = makeAddr("toko");
        noa = makeAddr("noa");

        vm.startPrank(admin);
        nft = new NFTCollection(
            admin,
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

        rewardToken = new GovernanceToken(GOV_MAX_SUPPLY, admin);

        staking = new NFTStaking(
            admin,
            address(nft),
            address(rewardToken),
            REWARD_RATE
        );
        rewardToken.grantRole(rewardToken.MINTER_ROLE(), address(staking));
        vm.stopPrank();

        _mintNFTsToUser(toko, 3);
        _mintNFTsToUser(noa, 3);

        vm.prank(toko);
        nft.setApprovalForAll(address(staking), true);

        vm.prank(noa);
        nft.setApprovalForAll(address(staking), true);
    }

    function _mintNFTsToUser(address user, uint256 quantity) internal {
        vm.deal(user, 10 ether);

        vm.prank(admin);
        nft.setPublicMintActive(true);

        vm.prank(user);
        nft.publicMint{value: 0.02 ether * quantity}(quantity);
    }
    function _stake(address user, uint256[] memory tokenIds) internal {
        vm.prank(user);
        staking.stake(tokenIds);
    }

    function _unstake(address user, uint256[] memory tokenIds) internal {
        vm.prank(user);
        staking.unstake(tokenIds);
    }

    function _warp(uint256 _seconds) internal {
        vm.warp(block.timestamp + _seconds);
    }
}
