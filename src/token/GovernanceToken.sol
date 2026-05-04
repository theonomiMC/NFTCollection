// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Thrown when amount is zero or otherwise invalid
error Gov_InvalidAmount();

/// @notice Thrown when a required address is zero
error Gov_InvalidAddress();

/// @notice Thrown when minting would exceed maximum token supply
error Gov_InsufficientSupply();

/// @title GovernanceToken
/// @author theonomiMC - Natalia Bakakuri
/// @notice ERC20 token with a capped total supply and role-based minting.
/// @dev Uses OpenZeppelin's AccessControl for permissioned minting. Only accounts
/// with `MINTER_ROLE` can mint new tokens. The total supply can never exceed `MAX_SUPPLY`.
contract GovernanceToken is ERC20, AccessControl {
    /// @notice Role allowed to mint new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Maximum number of tokens that can ever be minted.
    uint256 public immutable MAX_SUPPLY;

    /// @notice Initializes the governance token.
    /// @dev Sets the maximum supply and assigns admin role to `_admin`.
    /// @param maxSupply Maximum total supply of the token.
    /// @param _admin Address that receives `DEFAULT_ADMIN_ROLE`.
    constructor(
        uint256 maxSupply,
        address _admin
    ) ERC20("Governance Token", "GOV") {
        if (maxSupply == 0) revert Gov_InvalidAmount();
        if (_admin == address(0)) revert Gov_InvalidAddress();

        MAX_SUPPLY = maxSupply;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Mints new tokens to a specified address.
    /// @dev Can only be called by accounts with `MINTER_ROLE`.
    /// Reverts if minting would exceed `MAX_SUPPLY`.
    /// @param to Address receiving the minted tokens.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (to == address(0)) revert Gov_InvalidAddress();
        if (totalSupply() + amount > MAX_SUPPLY)
            revert Gov_InsufficientSupply();
        _mint(to, amount);
    }
}
