// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMintableERC20} from "../interfaces/ImintableERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*//////////////////////////////////////////////////////////////
                             CUSTOM ERRORS
//////////////////////////////////////////////////////////////*/
/// @notice Thrown when a required address is zero
error NFTStaking_InvalidAddress();

/// @notice Thrown when amount is invalid
error NFTStaking_InvalidAmount();

/// @notice Thrown when number of NFTs in a batch exceeds the max allowed size
error NFTStaking_BatchTooLarge();

/// @notice Thrown when caller is not the owner or staker of the NFT
error NFTStaking_NotOwner();

/// @notice Thrown when empty tokenId array is provided
error NFTStaking_EmptyArray();

/// @notice Thrown when user attempts to claim with no rewards available
error NFTStaking_NoReward();

/// @notice Thrown when attempting to stake the already staked NFT
error NFTStaking_AlreadyStaked();

/// @notice Thrown when an ERC721 token is received from unsupported NFT contract
error NFTStaking_InvalidNFT();

/// @notice Thrown when NFT transfered directly instead of through to staking flow
error NFTStaking_DirectTransferNotAllowed();

/// @title NFTStaking
/// @author theonomiMC - Natalia Bakakuri
/// @notice Allows users to stake NFTs, unstake NFTs, and claim ERC20 rewards earned over time
/// @dev Rewards are distributed using an accumulated reward-per-share accounting model.
/// Rewards are minted on claim through the configured reward token. The contract only accepts
/// NFTs transferred through the `stake` function and rejects direct ERC721 transfers.
contract NFTStaking is AccessControl, ReentrancyGuard, IERC721Receiver {
    /*//////////////////////////////////////////////////////////////
                            IMMUTABLES/CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice ERC721 collection accepted by this staking contract
    IERC721 public immutable nftCollection;

    /// @notice ERC20 reward token minted to users when rewards are claimed
    IMintableERC20 public immutable rewardToken;

    /// @notice Role allowed to update the reward emission rate
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");

    /// @notice Precision factor used for reward-per-share accounting
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum number of NFTs that can be staked or unstaked in one transaction
    uint256 public constant MAX_BATCH_SIZE = 50;

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Number of reward tokens emitted per second
    uint256 public rewardsPerSecond;

    /// @notice Accumulated rewards per staked NFT scaled by `PRECISION`
    uint256 public accRewardPerShare;

    /// @notice Total number of currently staked NFTs
    uint256 public totalStaked;

    /// @notice Timestamp of the last reward accounting update
    uint256 public lastUpdateTime;

    /// @notice Number of staked NFTs by each user
    mapping(address => uint256) public balanceOf;

    /// @notice address currently staking each NFT token ID
    mapping(uint256 => address) public stakerOf;

    /// @notice Rewards accrued but not yet calimed by each user
    mapping(address => uint256) public pendingRewards;

    /// @notice User reward checkpoint used to calculate newly accrued rewards
    mapping(address => uint256) public rewardCheckpoint;

    /// @dev List of NFT token IDs staked by each user
    mapping(address => uint256[]) internal userStakes;

    /// @dev Index of each staked token ID inside the owner's `userStakes` array
    mapping(uint256 => uint256) internal stakedTokenIndex;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when a user stakes an NFT
    /// @param user Address that staked the NFT
    /// @param tokenId Token ID of the staked NFT
    event Staked(address indexed user, uint256 tokenId);

    /// @notice Emitted when a user unstakes an NFT
    /// @param user Address that unstaked the NFT
    /// @param tokenId Token ID of the unstaked NFT
    event Unstaked(address indexed user, uint256 tokenId);

    /// @notice Emitted when the reward emission rate is updated
    /// @param _rewardPerSecond New reward token emission rate per second
    event RewardsRateUpdated(uint256 indexed _rewardPerSecond);

    /// @notice Emitted when a user claims rewards
    /// @param user Address that claimed rewards
    /// @param rewards Amount of reward tokens claimed
    event Claimed(address indexed user, uint256 rewards);

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the staking contract.
    /// @dev Grants both `DEFAULT_ADMIN_ROLE` and `REWARD_MANAGER_ROLE` to `_admin`.
    /// Sets the initial reward emission rate and initializes `lastUpdateTime`.
    /// @param _admin Address that receives admin and reward manager roles.
    /// @param _nftCollection ERC721 collection accepted for staking.
    /// @param _rewardToken ERC20 reward token minted on claim.
    /// @param _rewardsPerSecond Initial reward token emission rate per second.
    constructor(address _admin, address _nftCollection, address _rewardToken, uint256 _rewardsPerSecond) {
        if (_admin == address(0) || _nftCollection == address(0) || _rewardToken == address(0)) {
            revert NFTStaking_InvalidAddress();
        }
        if (_rewardsPerSecond == 0) revert NFTStaking_InvalidAmount();

        nftCollection = IERC721(_nftCollection);
        rewardToken = IMintableERC20(_rewardToken);
        rewardsPerSecond = _rewardsPerSecond;
        lastUpdateTime = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(REWARD_MANAGER_ROLE, _admin);
    }

    /// @notice Stakes one or more NFTs and starts earning rewards for the caller.
    /// @dev Updates global reward accounting and settles the caller's pending rewards
    /// before adding the new stake. The caller must own every token ID and must approve
    /// this contract before staking. Reverts if the batch is empty, too large, contains
    /// an already-staked NFT, or contains an NFT not owned by the caller.
    /// @param tokenIds NFT token IDs to stake.
    function stake(uint256[] calldata tokenIds) external nonReentrant {
        uint256 len = tokenIds.length;
        if (len == 0) revert NFTStaking_EmptyArray();
        if (len > MAX_BATCH_SIZE) revert NFTStaking_BatchTooLarge();

        _updatePool();
        _settle(msg.sender);

        balanceOf[msg.sender] += len;
        totalStaked += len;
        rewardCheckpoint[msg.sender] = (balanceOf[msg.sender] * accRewardPerShare) / PRECISION;

        for (uint256 i; i < len;) {
            uint256 tokenId = tokenIds[i];

            // verify msg.sender owns token on NFT contract
            if (stakerOf[tokenId] != address(0)) {
                revert NFTStaking_AlreadyStaked();
            }

            // verify not already staked
            if (nftCollection.ownerOf(tokenId) != msg.sender) {
                revert NFTStaking_NotOwner();
            }

            stakerOf[tokenId] = msg.sender;
            _addStakedToken(msg.sender, tokenId);

            // safeTransferFrom triggers onERC721Received.
            // This function is nonReentrant, and onERC721Received only accepts transfers
            // initiated by this contract, preventing direct deposits and reentrant stake flows.
            // If the transfer fails, all prior bookkeeping in this transaction is reverted.
            nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);

            emit Staked(msg.sender, tokenId);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Unstakes one or more NFTs and returns them to the caller.
    /// @dev Updates global reward accounting and settles the caller's pending rewards
    /// before removing the stake. The caller must be the recorded staker of every token ID.
    /// Uses swap-and-pop internally when removing token IDs from the user's stake list.
    /// Reverts if the batch is empty, too large, or contains an NFT not staked by the caller.
    /// @param tokenIds NFT token IDs to unstake.
    function unstake(uint256[] calldata tokenIds) external nonReentrant {
        uint256 len = tokenIds.length;
        if (len == 0) revert NFTStaking_EmptyArray();
        if (len > MAX_BATCH_SIZE) revert NFTStaking_BatchTooLarge();

        _updatePool();
        _settle(msg.sender);

        for (uint256 i; i < len;) {
            uint256 tokenId = tokenIds[i];

            if (stakerOf[tokenId] != msg.sender) revert NFTStaking_NotOwner();

            delete stakerOf[tokenId];
            _removeStakedToken(msg.sender, tokenId);

            emit Unstaked(msg.sender, tokenId);

            unchecked {
                ++i;
            }
        }

        balanceOf[msg.sender] -= len;
        totalStaked -= len;
        rewardCheckpoint[msg.sender] = (balanceOf[msg.sender] * accRewardPerShare) / PRECISION;

        for (uint256 i = 0; i < len;) {
            uint256 tokenId = tokenIds[i];
            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Claims all rewards earned by the caller.
    /// @dev Updates global reward accounting and settles the caller before minting rewards.
    /// Reverts if the caller has no claimable rewards.
    /// Emits a `Claimed` event
    function claim() external nonReentrant {
        _updatePool();
        _settle(msg.sender);

        uint256 rewards = pendingRewards[msg.sender];
        if (rewards == 0) revert NFTStaking_NoReward();

        pendingRewards[msg.sender] = 0;
        rewardToken.mint(msg.sender, rewards);

        emit Claimed(msg.sender, rewards);
    }

    /// @dev Updates global reward accounting based on time elapsed since `lastUpdateTime`.
    /// If no NFTs are staked, only updates `lastUpdateTime` so rewards are not accrued
    /// while the pool is empty. Updates `accRewardPerShare` using `PRECISION` scaling.
    function _updatePool() internal {
        if (block.timestamp <= lastUpdateTime) return;

        if (totalStaked == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - lastUpdateTime;
        uint256 reward = rewardsPerSecond * elapsed;
        accRewardPerShare += (reward * PRECISION) / totalStaked;
        lastUpdateTime = block.timestamp;
    }

    /// @dev Settles newly accrued rewards for `user` into `pendingRewards`.
    /// Calculates the user's accumulated rewards from `balanceOf[user]` and
    /// `accRewardPerShare`, then updates their `rewardCheckpoint`.
    /// @param user Address whose rewards should be settled.
    function _settle(address user) internal {
        uint256 accumulated = (balanceOf[user] * accRewardPerShare) / PRECISION;
        uint256 owed = accumulated - rewardCheckpoint[user];
        if (owed > 0) {
            pendingRewards[user] += owed;
        }
        rewardCheckpoint[user] = (balanceOf[user] * accRewardPerShare) / PRECISION;
    }

    /// @dev Adds `tokenId` to `user`'s staked token list and stores its array index.
    /// @param user Address staking the NFT.
    /// @param tokenId NFT token ID being added.
    function _addStakedToken(address user, uint256 tokenId) internal {
        userStakes[user].push(tokenId);
        stakedTokenIndex[tokenId] = userStakes[user].length - 1;
    }

    /// @dev Removes tokenId from user's staked token list using swap-and-pop.
    /// Assumes tokenId is currently staked by `user`.
    /// @param user Address staking the NFT.
    /// @param tokenId NFT token ID to remove.
    function _removeStakedToken(address user, uint256 tokenId) internal {
        uint256 lastIndex = userStakes[user].length - 1;
        uint256 index = stakedTokenIndex[tokenId];
        // swap
        if (index != lastIndex) {
            uint256 lastTokenId = userStakes[user][lastIndex];
            userStakes[user][index] = lastTokenId;
            stakedTokenIndex[lastTokenId] = index;
        }
        userStakes[user].pop();
        delete stakedTokenIndex[tokenId];
    }

    /// @notice Updates the reward token emission rate.
    /// @dev Can only be called by an account with `REWARD_MANAGER_ROLE`.
    /// Updates global reward accounting before changing the rate so the new rate
    /// only applies to future rewards.
    /// @param _newRate New reward token emission rate per second.
    function setRewardPerSecond(uint256 _newRate) external onlyRole(REWARD_MANAGER_ROLE) {
        if (_newRate == 0) revert NFTStaking_InvalidAmount();

        _updatePool();

        rewardsPerSecond = _newRate;
        emit RewardsRateUpdated(_newRate);
    }

    /// @notice Returns the total rewards currently claimable by `user`.
    /// @dev Includes both stored `pendingRewards` and rewards accrued since the last pool update.
    /// This function does not modify state.
    /// @param user Address to query.
    /// @return Total claimable reward token amount.
    function earned(address user) external view returns (uint256) {
        uint256 balance = balanceOf[user];
        if (balance == 0) {
            return pendingRewards[user];
        }
        uint256 currentAccRewardPerShare = accRewardPerShare;

        if (block.timestamp > lastUpdateTime && totalStaked != 0) {
            uint256 elapsed = block.timestamp - lastUpdateTime;
            uint256 rewards = elapsed * rewardsPerSecond;
            currentAccRewardPerShare += (rewards * PRECISION) / totalStaked;
        }
        uint256 accumulated = (balance * currentAccRewardPerShare) / PRECISION;
        uint256 owed = accumulated - rewardCheckpoint[user];

        return pendingRewards[user] + owed;
    }

    /// @notice Returns all NFT token IDs currently staked by `user`.
    /// @param user Address to query.
    /// @return Array of staked NFT token IDs.
    function stakedTokensOf(address user) external view returns (uint256[] memory) {
        return userStakes[user];
    }

    /// @notice Handles ERC721 safe transfers received by this contract.
    /// @dev Only accepts NFTs from the configured `nftCollection` and only when the
    /// transfer was initiated by this contract during `stake`. Direct user transfers
    /// are rejected to prevent untracked NFTs from becoming stuck.
    /// @param operator Address that initiated the ERC721 transfer.
    function onERC721Received(address operator, address, uint256, bytes calldata)
        external
        view
        override
        returns (bytes4)
    {
        if (msg.sender != address(nftCollection)) {
            revert NFTStaking_InvalidNFT();
        }
        if (operator != address(this)) {
            revert NFTStaking_DirectTransferNotAllowed();
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
