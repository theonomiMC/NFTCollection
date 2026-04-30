// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMintableERC20} from "../interfaces/ImintableERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {
    IERC721Receiver
} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// === Errors ===
error NFTStaking_InvalidAddress();
error NFTStaking_InvalidAmount();
error NFTStaking_NotOwner();
error NFTStaking_EmptyArray();
error NFTStaking_NoReward();
error NFTStaking_AlreadyStaked();
error NFTStaking_InvalidNFT();
error NFTStaking_DirectTransferNotAllowed();

contract NFTStaking is AccessControl, ReentrancyGuard, IERC721Receiver {
    IERC721 public immutable nftCollection;
    IMintableERC20 public immutable rewardToken;

    bytes32 public constant REWARD_MANAGER_ROLE =
        keccak256("REWARD_MANAGER_ROLE");

    uint256 public constant PRECISION = 1e18;

    uint256 public rewardsPerSecond;
    uint256 public accRewardPerShare;
    uint256 public totalStaked;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public balanceOf;
    mapping(uint256 => address) public stakerOf;
    mapping(address => uint256) public pendingRewards;
    mapping(address => uint256) public rewardCheckpoint;
    mapping(address => uint256[]) internal userStakes;
    mapping(uint256 => uint256) internal stakedTokenIndex;

    event Staked(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId);
    event RewardsRateUpdated(uint256 indexed _rewardPerSecond);
    event Claimed(address indexed user, uint256 rewards);

    constructor(
        address _admin,
        address _nftCollection,
        address _rewardToken,
        uint256 _rewardsPerSecond
    ) {
        if (
            _admin == address(0) ||
            _nftCollection == address(0) ||
            _rewardToken == address(0)
        ) {
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

    function stake(uint256[] calldata tokenIds) external nonReentrant {
        uint256 len = tokenIds.length;
        if (len == 0) revert NFTStaking_EmptyArray();

        _updatePool();
        _settle(msg.sender);

        for (uint256 i; i < len; ) {
            uint256 tokenId = tokenIds[i];

            // verify msg.sender owns token on NFT contract
            if (stakerOf[tokenId] != address(0)) {
                revert NFTStaking_AlreadyStaked();
            }

            // verify not already staked
            if (nftCollection.ownerOf(tokenId) != msg.sender) {
                revert NFTStaking_NotOwner();
            }

            nftCollection.safeTransferFrom(msg.sender, address(this), tokenId);
            stakerOf[tokenId] = msg.sender;

            _addStakedToken(msg.sender, tokenId);

            emit Staked(msg.sender, tokenId);

            unchecked {
                ++i;
            }
        }
        balanceOf[msg.sender] += len;
        totalStaked += len;
        rewardCheckpoint[msg.sender] =
            (balanceOf[msg.sender] * accRewardPerShare) /
            PRECISION;
    }

    function unstake(uint256[] calldata tokenIds) external nonReentrant {
        uint256 len = tokenIds.length;
        if (len == 0) revert NFTStaking_EmptyArray();

        _updatePool();
        _settle(msg.sender);

        for (uint256 i; i < len; ) {
            uint256 tokenId = tokenIds[i];

            // verify msg.sender owns token on NFT contract
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
        rewardCheckpoint[msg.sender] =
            (balanceOf[msg.sender] * accRewardPerShare) /
            PRECISION;

        for (uint256 i = 0; i < len; ) {
            uint256 tokenId = tokenIds[i];
            nftCollection.safeTransferFrom(address(this), msg.sender, tokenId);

            unchecked {
                ++i;
            }
        }
    }

    function claim() external nonReentrant {
        _updatePool();
        _settle(msg.sender);

        uint256 rewards = pendingRewards[msg.sender];
        if (rewards == 0) revert NFTStaking_NoReward();

        pendingRewards[msg.sender] = 0;
        rewardToken.mint(msg.sender, rewards);

        emit Claimed(msg.sender, rewards);
    }

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

    function _settle(address user) internal {
        uint256 accumulated = (balanceOf[user] * accRewardPerShare) / PRECISION;
        uint256 owed = accumulated - rewardCheckpoint[user];
        if (owed > 0) {
            pendingRewards[user] += owed;
        }
        rewardCheckpoint[user] =
            (balanceOf[user] * accRewardPerShare) /
            PRECISION;
    }

    function _addStakedToken(address user, uint256 tokenId) internal {
        userStakes[user].push(tokenId);
        stakedTokenIndex[tokenId] = userStakes[user].length - 1;
    }

    /// @dev Removes tokenId from user's staked token list using swap-and-pop.
    /// Assumes tokenId is currently staked by `user`.
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

    function setRewardPerSecond(
        uint256 _newRate
    ) external onlyRole(REWARD_MANAGER_ROLE) {
        if (_newRate == 0) revert NFTStaking_InvalidAmount();

        _updatePool();

        rewardsPerSecond = _newRate;
        emit RewardsRateUpdated(_newRate);
    }

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

    function stakedTokensOf(
        address user
    ) external view returns (uint256[] memory) {
        return userStakes[user];
    }

    function onERC721Received(
        address operator,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        if (msg.sender != address(nftCollection)) {
            revert NFTStaking_InvalidNFT();
        }
        if (operator != address(this)) {
            revert NFTStaking_DirectTransferNotAllowed();
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
