// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {NFTStaking} from "../../src/staking/NFTStaking.sol";

contract MaliciousNFT is ERC721 {
    NFTStaking public staking;
    bool public attackEnabled;
    bool public reentrancyFailed;

    constructor() ERC721("Bad", "BAD") {}

    function setTarget(NFTStaking _staking) external {
        staking = _staking;
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function enableAttack() external {
        attackEnabled = true;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address previousOwner) {
        previousOwner = super._update(to, tokenId, auth);

        if (attackEnabled && to == address(staking)) {
            try staking.claim() {}
            catch {
                reentrancyFailed = true;
            }
        }
    }
}
