// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BaseTest} from "../base/BaseTest.t.sol";
import {NftHandler} from "../handlers/NftHandler.sol";

contract NFTCollectionInvariantTest is StdInvariant, BaseTest {
    using Strings for uint256;

    NftHandler public handler;
    address[] public users;

    function setUp() public override {
        super.setUp();

        users.push(toko);
        users.push(noa);

        users = new address[](3);
        users[0] = toko;
        users[1] = noa;
        users[2] = makeAddr("User C");

        handler = new NftHandler(nft, MAX_SUPPLY, users);

        targetContract(address(handler));
    }

    function invariant_ContractETHBalanceMatchesExpectedBalance() public view {
        assertGe(address(nft).balance, handler.expectedBalance());
    }

    function invariant_TotalSupplyMatchesExpectedSupply() public view {
        assertEq(nft.totalSupply(), handler.expectedTotalSupply());
    }

    function invariant_TotalSupplyNeverExceedsMaxSupply() public view {
        assertLe(nft.totalSupply(), MAX_SUPPLY);
    }

    function invariant_TotalSupplyEqualsSumUserBalances() public view {
        uint256 len = users.length;
        uint256 SumUserBalances;

        for (uint256 i; i < len; i++) {
            address user = users[i];

            uint256 userBalance = nft.balanceOf(user);
            SumUserBalances += userBalance;
        }
        assertEq(SumUserBalances, nft.totalSupply());
    }

    function invariant_UserBalancesNeverExceedWalletLimit() public view {
        uint256 len = users.length;

        for (uint256 i; i < len; i++) {
            address user = users[i];

            assertLe(nft.balanceOf(user), nft.maxMintPerAddress());
        }
    }

    // function invariant_TokenURI_MatchesRevealState() public view {
    //     uint256 supply = nft.totalSupply();

    //     for (uint256 tokenId = 1; tokenId <= supply; tokenId++) {
    //         string memory actualUri = nft.tokenURI(tokenId);
    //         if (!nft.isRevealed()) {
    //             assertEq(
    //                 keccak256(bytes(actualUri)),
    //                 keccak256(bytes(nft.hiddenURI()))
    //             );
    //         } else {
    //             assertEq(
    //                 keccak256(bytes(actualUri)),
    //                 keccak256(
    //                     bytes(
    //                         string.concat(
    //                             "ipfs://test/",
    //                             tokenId.toString(),
    //                             ".json"
    //                         )
    //                     )
    //                 )
    //             );
    //         }
    //     }
    // }

}

