// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NFTStaking} from "../../src/staking/NFTStaking.sol";
import {NFTCollection} from "../../src/nft/NFTCollection.sol";

contract StakingHandler is Test {
    NFTStaking public staking;
    NFTCollection public nft;

    address[] public users;
    uint256[] public tokenIds;

    uint256 public expectedTotalClaimed;

    constructor(
        NFTStaking _staking,
        NFTCollection _nft,
        address[] memory _users,
        uint256[] memory _tokenIds
    ) {
        staking = _staking;
        nft = _nft;
        users = _users;
        tokenIds = _tokenIds;
    }

    function stake(uint256 userSeed, uint256 tokenSeed) external {
        address user = users[userSeed % users.length];
        uint256 tokenId = tokenIds[tokenSeed % tokenIds.length];

        if (staking.stakerOf(tokenId) != address(0)) return;

        try nft.ownerOf(tokenId) returns (address owner) {
            if (owner != user) return;
        } catch {
            return;
        }
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;

        vm.prank(user);
        staking.stake(ids);
    }

    function unstake(uint256 userSeed, uint256 tokenSeed) external {
        address user = users[userSeed % users.length];
        uint256 tokenId = tokenIds[tokenSeed % tokenIds.length];

        if (staking.stakerOf(tokenId) != user) return;

        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;

        vm.prank(user);
        staking.unstake(ids);
    }

    function claim(uint256 userSeed) external {
        address user = users[userSeed % users.length];
        uint256 amountToClaim = staking.earned(user);
        vm.prank(user);
        try staking.claim() {
            expectedTotalClaimed += amountToClaim;
        } catch {}
    }

    function warp(uint256 timeJump) external {
        timeJump = bound(timeJump, 1, 30 days);
        vm.warp(block.timestamp + timeJump);
    }
}
