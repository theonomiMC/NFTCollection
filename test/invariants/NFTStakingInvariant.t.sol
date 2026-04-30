// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "../base/BaseTest.t.sol";
import {StakingHandler} from "../handlers/StakingHandler.sol";

contract NFTStakingInvariantTest is BaseTest {
    StakingHandler internal handler;

    address[] internal users;
    uint256[] internal tokenIds;

    function setUp() public override {
        super.setUp();

        users.push(toko);
        users.push(noa);

        for (uint256 i = 1; i < 7; i++) {
            tokenIds.push(i);
        }

        handler = new StakingHandler(staking, nft, users, tokenIds);

        targetContract(address(handler));
    }
    function invariant_TotalStakedEqualsNFTBalance() public view {
        uint256 actualNFTBalance = nft.balanceOf(address(staking));
        uint256 totalStaked = staking.totalStaked();

        assertEq(totalStaked, actualNFTBalance);
    }
    function invariant_TotalStakedEqualsUserBalances() public view {
        uint256 sum;
        uint256 len = users.length;
        for (uint256 i; i < len; i++) {
            sum += staking.balanceOf(users[i]);
        }

        assertEq(staking.totalStaked(), sum);
    }
    function invariant_BalanceMatchesStakedTokenListLength() public view {
        uint256 len = users.length;
        for (uint256 i; i < len; i++) {
            address user = users[i];
            uint256 balance = staking.balanceOf(user);
            uint256[] memory stakedTokens = staking.stakedTokensOf(user);

            assertEq(balance, stakedTokens.length);
        }
    }
    function invariant_StakedTokensAreOwnedByStakingContract() public view {
        uint256 len = users.length;
        for (uint256 i; i < len; i++) {
            address user = users[i];
            uint256[] memory stakedTokens = staking.stakedTokensOf(user);

            uint256 stakedLen = stakedTokens.length;

            for (uint256 j; j < stakedLen; j++) {
                uint256 token = stakedTokens[j];
                assertEq(nft.ownerOf(token), address(staking));
                assertEq(staking.stakerOf(token), address(user));
            }
        }
    }

    function invariant_Earned_AlwaysGreaterOrEqualToPending() public view {
        uint256 len = users.length;
        for (uint256 i; i < len; i++) {
            address user = users[i];

            uint256 earned = staking.earned(user);
            uint256 pendingAmount = staking.pendingRewards(user);

            assertGe(earned, pendingAmount);
        }
    }

    function invariant_RewardCheckpoint_NeverExceedsMaxAccumulated()
        public
        view
    {
        uint256 len = users.length;
        for (uint256 i; i < len; i++) {
            address user = users[i];

            uint256 accumulated = (staking.balanceOf(user) *
                staking.accRewardPerShare()) / staking.PRECISION();

            assertLe(staking.rewardCheckpoint(user), accumulated);
        }
    }

    function invariant_TotalSupply_EqualsTotalClaimed() public view {
        assertEq(rewardToken.totalSupply(), handler.expectedTotalClaimed());
    }

    function invariant_NoDuplicate_Tokens_Per_User() public view {
        uint256 len = users.length;
        for (uint256 i; i < len; i++) {
            address user = users[i];

            uint256[] memory stakedTokens = staking.stakedTokensOf(user);
            uint256 tokenLen = stakedTokens.length;

            for (uint256 j; j < tokenLen; j++) {
                for (uint256 k=j+1; k < tokenLen; k++) {
                    if (k != j) {
                        assertNotEq(stakedTokens[k], stakedTokens[j]);
                    }
                }
            }
        }
    }
    function invariant_UnstakedTokensAreNotOwnedByStakingContract() public view {
        uint256 len = tokenIds.length;

        for(uint256 i; i<len; i++){
            uint256 id = tokenIds[i];
            if(staking.stakerOf(id) == address(0)){
                assertNotEq(nft.ownerOf(id), address(staking));
            }
        }
    }

    function invariant_GovToken_NeverExceedsMaxSupply() public view {
        // GOV_MAX_SUPPLY is inherited from BaseTest (1_000_000 ether)
        assertLe(rewardToken.totalSupply(), GOV_MAX_SUPPLY);
    }
}
