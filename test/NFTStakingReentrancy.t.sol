// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MaliciousNFT} from "./mock/MaliciousNFT.sol";
import {NFTStaking} from "../src/staking/NFTStaking.sol";
import {GovernanceToken} from "../src/token/GovernanceToken.sol";

contract NftStakingReentrancyTest is Test {
    MaliciousNFT public maliciousNFT;
    NFTStaking public staking;
    GovernanceToken public rewardToken;

    address internal multisig;
    address internal attackerUser;

    uint256 internal constant REWARD_RATE = 10;
    uint256 internal constant MAX_SUPPLY = 1000;
    uint256 internal constant GOV_MAX_SUPPLY = 1_000_000 ether;

    function setUp() public {
        multisig = makeAddr("multisig");
        attackerUser = makeAddr("attackerUser");

        maliciousNFT = new MaliciousNFT();

        vm.startPrank(multisig);

        rewardToken = new GovernanceToken(GOV_MAX_SUPPLY, multisig);
        staking = new NFTStaking(multisig, address(maliciousNFT), address(rewardToken), REWARD_RATE);

        rewardToken.grantRole(rewardToken.MINTER_ROLE(), address(staking));

        vm.stopPrank();

        maliciousNFT.setTarget((staking));
        maliciousNFT.mint(attackerUser, 1);

        vm.prank(attackerUser);
        maliciousNFT.setApprovalForAll(address(staking), true);
    }

    function test_ReentrancyDuringStake_FailsButOuterStakeSucceeds() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;

        maliciousNFT.enableAttack();

        vm.prank(attackerUser);
        staking.stake(ids);

        assertTrue(maliciousNFT.reentrancyFailed());
        assertEq(staking.stakerOf(1), attackerUser);
        assertEq(staking.balanceOf(attackerUser), 1);
        assertEq(staking.totalStaked(), 1);
        assertEq(maliciousNFT.ownerOf(1), address(staking));
    }
}
