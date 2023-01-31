// SPDX-License-Identifier: MIT
// Creator: Amar
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Stake is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Interfaces for ERC20 and ERC721
    IERC20 public immutable rewardsToken;
    IERC721 public immutable nftCollection;

    uint256 mintimeperiod = 1 days;
    uint256 maxtimeperiod = 90 days;
    uint256 max_rewards_perNFT;

    event withdraw_status(
        uint256 nft_id,
        uint256 nft_withdrawn_time,
        uint256 current_rewards
    );
    event rewards_status(
        uint256 timeofclaim,
        uint256 NFTs_staked,
        uint256 clamed_rewards
    );

    struct tokendetails {
        //token owner
        address owner;
        // staked time
        uint256 staketime;
        //current rewards which are staked out
        uint256 present_rewards;
        // rewards which can be clamed out
        uint256 claimable_rewards;
        // updated time while rewards clammed
        uint256 timeOfLastUpdate;
    }
    // Details of the respective token
    mapping(uint256 => tokendetails) public stakeIDs;
    // user info of the staked tokens
    mapping(address => uint256[]) internal usersNFT;
    // rewards allocated per day
    uint256 private rewardsPerDay;

    constructor(
        IERC721 _nftCollection,
        IERC20 _rewardsToken,
        uint rewardsperday,
        uint max_rewards_per_nft
    ) {
        nftCollection = _nftCollection;
        rewardsToken = _rewardsToken;
        rewardsPerDay = rewardsperday;
        max_rewards_per_nft=max_rewards_perNFT;
    }

    // NFT staking function
    function stake(uint256 _tokenId) external nonReentrant {
        require(
            nftCollection.ownerOf(_tokenId) == msg.sender,
            "Can't stake tokens you don't own!"
        );

        nftCollection.transferFrom(msg.sender, address(this), _tokenId);

        usersNFT[msg.sender].push(_tokenId);

        stakeIDs[_tokenId] = tokendetails(msg.sender, block.timestamp, 0, 0, 0);
    }

    // extracting the Nft from the contract to users address
    function withdraw(uint256 _tokenId) external nonReentrant {
        require(
            stakeIDs[_tokenId].owner == msg.sender,
            "withdrawer is not the owner of the NFTs"
        );

        require(
            (block.timestamp - stakeIDs[_tokenId].staketime) >= mintimeperiod,
            "The NFT should be staked atleast for a day"
        );

        calculateRewards(msg.sender);

        nftCollection.transferFrom(address(this), msg.sender, _tokenId);

        rewardsToken.safeTransfer(
            msg.sender,
            stakeIDs[_tokenId].claimable_rewards
        );

        uint256[] storage total_tokens = usersNFT[msg.sender];
        for (uint256 i; i < total_tokens.length; i++) {
            if (total_tokens[i] == _tokenId) {
                total_tokens[i] = total_tokens[total_tokens.length - 1];
                total_tokens.pop();
                break;
            }
        }

        emit withdraw_status(
            _tokenId,
            block.timestamp,
            stakeIDs[_tokenId].claimable_rewards
        );

        stakeIDs[_tokenId] = tokendetails(address(0), 0, 0, 0, 0);
    }

    // getting the rewards clamed by staking the NFTs
    function claimRewards() external nonReentrant{
        uint256[] memory tokens = usersNFT[msg.sender];
        uint256 rewards;
        calculateRewards(msg.sender);

        for (uint256 i; i < tokens.length; i++) {
            rewards += stakeIDs[tokens[i]].claimable_rewards;
            stakeIDs[tokens[i]].timeOfLastUpdate = block.timestamp;
            stakeIDs[tokens[i]].claimable_rewards = 0;
        }
        require(rewards > 0, "You have no rewards to claim");
        rewardsToken.safeTransfer(msg.sender, rewards);

        emit rewards_status(block.timestamp, tokens.length, rewards);
    }
    //////////
    // View //
    //////////

    // To know that the user had staked NFT or not
    function StakeInfo(uint256 tokenID) internal view returns (address) {
        address token_user = stakeIDs[tokenID].owner;
        return token_user;
    }

    // To know the rewards for the staked NFTs
    function availableRewards() external view returns (uint256) {
        uint256[] memory tokens = usersNFT[msg.sender];
        uint256 _rewards;
        for (uint256 i; i < tokens.length; i++) {
            if (stakeIDs[tokens[i]].timeOfLastUpdate == 0) {
                if (
                    block.timestamp - stakeIDs[tokens[i]].staketime <=
                    maxtimeperiod
                ) {
                    uint256 rewards = (((block.timestamp -
                        stakeIDs[tokens[i]].staketime) / 60) * rewardsPerDay);
                    _rewards += rewards;
                } else {
                    _rewards += max_rewards_perNFT;
                }
            } else {
                uint256 rewards = (((block.timestamp -
                    stakeIDs[tokens[i]].timeOfLastUpdate) / 60) *
                    rewardsPerDay);
                if (
                    rewards + stakeIDs[tokens[i]].present_rewards <=
                    max_rewards_perNFT
                ) {
                    _rewards += rewards;
                } else {
                    _rewards +=
                        max_rewards_perNFT -
                        stakeIDs[tokens[i]].present_rewards;
                }
            }
        }
        return _rewards;
    }

    /////////////
    // Internal//
    /////////////

    // Calculate rewards for param _staker by calculating the time passed
    // since last update in Days and mulitplying it to ERC721 Tokens Staked
    // and rewardsPerDay.

    function calculateRewards(address _staker) internal {
        uint256[] memory tokens = usersNFT[_staker];

        for (uint256 i; i < tokens.length; i++) {
            if (stakeIDs[tokens[i]].timeOfLastUpdate == 0) {
                if (
                    block.timestamp - stakeIDs[tokens[i]].staketime <=
                    maxtimeperiod
                ) {
                    uint256 rewards = (((block.timestamp -
                        stakeIDs[tokens[i]].staketime) / 60) * rewardsPerDay);
                    stakeIDs[tokens[i]].present_rewards = rewards;
                    stakeIDs[tokens[i]].claimable_rewards = rewards;
                } else {
                    stakeIDs[tokens[i]].present_rewards = max_rewards_perNFT;
                    stakeIDs[tokens[i]].claimable_rewards = max_rewards_perNFT;
                }
            } else {
                uint256 rewards = (((block.timestamp -
                    stakeIDs[tokens[i]].timeOfLastUpdate) / 60) *
                    rewardsPerDay);

                if (
                    rewards + stakeIDs[tokens[i]].present_rewards <=
                    max_rewards_perNFT
                ) {
                    stakeIDs[tokens[i]].present_rewards += rewards;
                    stakeIDs[tokens[i]].claimable_rewards += rewards;
                } else {
                    stakeIDs[tokens[i]].claimable_rewards =
                        max_rewards_perNFT -
                        stakeIDs[tokens[i]].present_rewards;
                    stakeIDs[tokens[i]].present_rewards = max_rewards_perNFT;
                }
            }
        }
    }
}
