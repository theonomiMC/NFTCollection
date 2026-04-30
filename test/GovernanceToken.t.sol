// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./base/BaseTest.t.sol";
import {
    GovernanceToken,
    Gov_InvalidAmount,
    Gov_InvalidAddress,
    Gov_InsufficientSupply
} from "../src/token/GovernanceToken.sol";

contract GovernanceTokenTest is BaseTest {
    function test_InitialStates() public view {
        assertEq(rewardToken.MAX_SUPPLY(), GOV_MAX_SUPPLY);
        assertTrue(
            rewardToken.hasRole(rewardToken.DEFAULT_ADMIN_ROLE(), admin)
        );
    }
    function test_Constructor_InvalidAdminAddress_Reverts() public {
        vm.expectRevert(Gov_InvalidAddress.selector);
        new GovernanceToken(GOV_MAX_SUPPLY, address(0));
    }
    function test_Constructor_ZeroMaxSupply_Reverts() public {
        vm.expectRevert(Gov_InvalidAmount.selector);
        new GovernanceToken(0, admin);
    }
    function test_Gov_Mint_ExceedsMaxSupply_Reverts() public {
        vm.startPrank(admin);
        rewardToken.grantRole(rewardToken.MINTER_ROLE(), admin);

        vm.expectRevert(Gov_InsufficientSupply.selector);
        rewardToken.mint(toko, GOV_MAX_SUPPLY + 1);

        vm.stopPrank();
    }
    function test_Gov_Mint_NonMinter_Reverts() public {
        vm.prank(toko);
        vm.expectRevert();
        rewardToken.mint(toko, 1 ether);
    }
    function test_Gov_Mint_ExactlyMaxSupply_Succeeds() public {
        vm.startPrank(admin);
        rewardToken.grantRole(rewardToken.MINTER_ROLE(), admin);
        rewardToken.mint(toko, GOV_MAX_SUPPLY);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(toko), GOV_MAX_SUPPLY);
    }
    function test_Gov_Mint_UpdatesTotalSupply() public {
        vm.startPrank(admin);
        rewardToken.grantRole(rewardToken.MINTER_ROLE(), admin);
        rewardToken.mint(toko, 100 ether);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(toko), 100 ether);
        assertEq(rewardToken.totalSupply(), 100 ether);
    }
    function test_Gov_Mint_CumulativeSupplyCannotExceedMax() public {
        vm.startPrank(admin);
        rewardToken.grantRole(rewardToken.MINTER_ROLE(), admin);

        rewardToken.mint(toko, GOV_MAX_SUPPLY - 1);

        vm.expectRevert(Gov_InsufficientSupply.selector);
        rewardToken.mint(noa, 2);

        vm.stopPrank();
    }
}
