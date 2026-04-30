// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./base/BaseTest.t.sol";
import {
    NFTStaking,
    NFTStaking_NoReward,
    NFTStaking_InvalidAddress,
    NFTStaking_InvalidAmount,
    NFTStaking_EmptyArray,
    NFTStaking_AlreadyStaked,
    NFTStaking_NotOwner,
    NFTStaking_InvalidNFT,
    NFTStaking_DirectTransferNotAllowed
} from "../src/staking/NFTStaking.sol";

contract NFTStakingTest is BaseTest {
    function test_InitialStates() public view {
        assertEq(address(staking.nftCollection()), address(nft));
        assertEq(address(staking.rewardToken()), address(rewardToken));

        assertEq(staking.PRECISION(), 1e18);

        assertEq(staking.totalStaked(), 0);
        assertEq(staking.rewardsPerSecond(), REWARD_RATE);
        assertEq(staking.accRewardPerShare(), 0);
        assertEq(staking.lastUpdateTime(), block.timestamp);

        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(staking.hasRole(staking.REWARD_MANAGER_ROLE(), admin));
    }
    function test_Constructor_ZeroAdminAddress_Reverts() public {
        vm.expectRevert(NFTStaking_InvalidAddress.selector);
        new NFTStaking(
            address(0),
            address(nft),
            address(rewardToken),
            REWARD_RATE
        );
    }
    function test_Constructor_ZeroRewardTokenAddress_Reverts() public {
        vm.expectRevert(NFTStaking_InvalidAddress.selector);
        new NFTStaking(admin, address(nft), address(0), REWARD_RATE);
    }

    function test_Constructor_ZeroRewardRate_Reverts() public {
        vm.expectRevert(NFTStaking_InvalidAmount.selector);
        new NFTStaking(admin, address(nft), address(rewardToken), 0);
    }
    function test_Stake_SingleNFT_UpdatesState() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        _stake(toko, tokenIds);

        assertEq(staking.balanceOf(toko), 1);
        assertEq(staking.totalStaked(), 1);
        assertEq(nft.ownerOf(1), address(staking));
        assertEq(staking.stakerOf(1), toko);
        assertEq(staking.stakedTokensOf(toko).length, 1);
        assertEq(staking.stakedTokensOf(toko)[0], 1);
    }
    function test_claimReward_singleUser() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        _stake(toko, tokenIds);
        _warp(10 seconds);

        vm.prank(toko);
        staking.claim();

        assertEq(rewardToken.balanceOf(toko), 100);
        assertEq(staking.pendingRewards(toko), 0);
        assertEq(staking.balanceOf(toko), 2);
        assertEq(staking.totalStaked(), 2);
    }
    function test_rewardAccount() public {
        uint256[] memory tokoIds = new uint256[](1);
        tokoIds[0] = 1;

        uint256[] memory noaIds = new uint256[](1);
        noaIds[0] = 4;

        _stake(toko, tokoIds);

        _warp(10 seconds);

        _stake(noa, noaIds);

        assertEq(staking.earned(toko), 100);
        assertEq(staking.earned(noa), 0);
    }
    function test_Stake_EmptyArray_Reverts() public {
        vm.prank(toko);
        vm.expectRevert(NFTStaking_EmptyArray.selector);
        staking.stake(new uint256[](0));
    }
    function test_Stake_NotOwner_Reverts() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1; // this nft is minted for Toko

        vm.prank(noa);
        vm.expectRevert(NFTStaking_NotOwner.selector);
        staking.stake(tokenIds);

        assertEq(nft.ownerOf(1), toko);
    }
    function test_Unstake_SingleNFT_UpdatesStateAndReturnsOwnership() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        _stake(toko, tokenIds);

        assertEq(nft.ownerOf(1), address(staking));

        _unstake(toko, tokenIds);

        assertEq(nft.ownerOf(1), toko);
        assertEq(staking.stakerOf(1), address(0));
        assertEq(staking.balanceOf(toko), 0);
        assertEq(staking.totalStaked(), 0);
    }

    function test_Unstake_NotStaker_Reverts() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        _stake(toko, tokenIds);

        vm.prank(noa);
        vm.expectRevert(NFTStaking_NotOwner.selector);
        staking.unstake(tokenIds);
    }
    function test_Stake_AlreadyStaked_Reverts() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        _stake(toko, ids);

        vm.prank(toko);
        vm.expectRevert(NFTStaking_AlreadyStaked.selector);
        staking.stake(ids);
    }
    function test_Claim_NoRewards_Reverts() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 4;

        _stake(noa, tokenIds);

        vm.prank(noa);
        vm.expectRevert(NFTStaking_NoReward.selector);
        staking.claim();
    }
    function test_Stake_MultipleNFTs_UpdatesState() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        _stake(toko, ids);

        assertEq(staking.stakedTokensOf(toko), ids);
        assertEq(staking.stakerOf(1), toko);
        assertEq(staking.stakerOf(2), toko);
        assertEq(nft.ownerOf(1), address(staking));
        assertEq(nft.ownerOf(2), address(staking));
        assertEq(staking.totalStaked(), 2);
    }
    function test_Unstake_UpdatesEnumeration_WithSwapAndPop() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        _stake(toko, ids);

        uint256[] memory removeIds = new uint256[](1);
        removeIds[0] = 2;
        _unstake(toko, removeIds);

        uint256[] memory remaining = staking.stakedTokensOf(toko);

        assertEq(staking.totalStaked(), 2);
        assertEq(staking.balanceOf(toko), 2);
        assertEq(nft.ownerOf(2), toko);
        assertEq(staking.stakerOf(1), toko);
        assertEq(staking.stakerOf(3), toko);
        assertEq(remaining.length, 2);
        assertEq(staking.stakerOf(2), address(0));
    }
    function test_Claim_SingleUser_LeavesStakeStateUnchanged() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        _stake(toko, ids);

        _warp(10 seconds);

        vm.prank(toko);
        staking.claim();

        assertEq(staking.balanceOf(toko), 1);
        assertEq(staking.totalStaked(), 1);
        assertEq(nft.ownerOf(1), address(staking));
        assertEq(staking.stakerOf(1), toko);
        assertEq(staking.pendingRewards(toko), 0);
    }

    function test_Unstake_EmptyArray_Reverts() public {
        vm.prank(toko);
        vm.expectRevert(NFTStaking_EmptyArray.selector);
        staking.unstake(new uint256[](0));
    }

    function test_Accounting_LateStaker_SharesFutureRewardsOnly() public {
        uint256[] memory tokoIds = new uint256[](1);
        tokoIds[0] = 1;

        _stake(toko, tokoIds);

        _warp(10 seconds);

        uint256[] memory noaIds = new uint256[](1);
        noaIds[0] = 4;

        _stake(noa, noaIds);

        _warp(10 seconds);

        assertEq(staking.earned(toko), 150);
        assertEq(staking.earned(noa), 50);
    }
    function test_Accounting_RewardRateChange_AffectsOnlyFutureRewards()
        public
    {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        _stake(toko, ids);

        _warp(10 seconds);

        vm.prank(admin);
        staking.setRewardPerSecond(20);

        _warp(10 seconds);

        assertEq(staking.earned(toko), 300);
    }
    // REWARD RATE
    function test_SetRewardPerSecond_UpdatesRate() public {
        uint256 newRate = 20;

        vm.prank(admin);
        staking.setRewardPerSecond(newRate);

        assertEq(staking.rewardsPerSecond(), newRate);
    }
    function test_SetRewardPerSecond_ZeroAmount_Reverts() public {
        vm.prank(admin);
        // Add the custom error selector check once you import it
        vm.expectRevert(NFTStaking_InvalidAmount.selector);
        staking.setRewardPerSecond(0);
    }
    function test_SetRewardPerSecond_NotManager_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        staking.setRewardPerSecond(20);
    }
    function test_ZeroBalance_PendingRewards() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        _stake(toko, ids);

        _unstake(toko, ids);

        assertEq(staking.pendingRewards(toko), staking.earned(toko));
    }
    function test_UpdatePool_ZeroStaked() public {
        _warp(10 seconds);
        
        vm.prank(admin);
        staking.setRewardPerSecond(20);
        
        assertEq(staking.lastUpdateTime(), block.timestamp);
    }
    function test_DirectNFTTransfer_CreatesUntrackedStuckNFT() public {
        uint256 tokenId = 1;

        assertEq(nft.ownerOf(tokenId), toko);

        vm.prank(toko);
        vm.expectRevert(NFTStaking_DirectTransferNotAllowed.selector);
        nft.safeTransferFrom(toko, address(staking), tokenId);

    }
}
