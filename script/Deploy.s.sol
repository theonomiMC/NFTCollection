// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {NFTCollection} from "../src/nft/NFTCollection.sol";
import {NFTStaking} from "../src/staking/NFTStaking.sol";
import {GovernanceToken} from "../src/token/GovernanceToken.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy NFT Collection
        NFTCollection nft = new NFTCollection(
            initialOwner,
            "Tanaka NFT",
            "TNFT",
            1000, // maxSupply
            0.01 ether, // whitelistPrice
            0.02 ether, // publicPrice
            10, // maxMintPerAddress
            "ipfs://hidden.json",
            initialOwner,
            500 // royaltyBps
        );
        console2.log("NFTCollection deployed at:", address(nft));

        // 2. Deploy Governance token
        GovernanceToken rewardToken = new GovernanceToken(10_000_000 ether, initialOwner);
        console2.log("GovernanceToken deployed at:", address(rewardToken));

        // 3. Deploy Staking contract
        NFTStaking staking = new NFTStaking(
            initialOwner,
            address(nft),
            address(rewardToken),
            10000000000000000 // rewardsPerSecond
        );
        console2.log("NFTStaking deployed at:", address(staking));

        rewardToken.grantRole(rewardToken.MINTER_ROLE(), address(staking));

        vm.stopBroadcast();
    }
}
