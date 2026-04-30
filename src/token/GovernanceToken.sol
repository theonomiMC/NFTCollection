// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

error Gov_InvalidAmount();
error Gov_InvalidAddress();
error Gov_InsufficientSupply();

contract GovernanceToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public immutable MAX_SUPPLY;

    constructor(uint256 maxSupply, address _admin) ERC20("Governance Token", "GOV") {
        if (maxSupply == 0) revert Gov_InvalidAmount();
        if(_admin == address(0)) revert Gov_InvalidAddress();

        MAX_SUPPLY = maxSupply;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > MAX_SUPPLY) revert Gov_InsufficientSupply();
        _mint(to, amount);
    }
}
