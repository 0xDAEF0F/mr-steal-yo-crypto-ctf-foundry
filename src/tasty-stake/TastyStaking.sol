//SPDX-License-Identifier: MIT
pragma solidity =0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * Based on synthetix BaseRewardPool.sol & convex cvxLocker
 */
contract TastyStaking is Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    IERC20 public stakingToken;
    address public rewardDistributor;

    uint256 public constant DURATION = 86400 * 7; // fixed duration for rewards (7 days)
    // @audit-ok total amount staked
    uint256 public totalSupply;

    address[] public rewardTokens;

    mapping(address user => uint256 stakedAmount) public balanceOf;
    mapping(address rewardToken => Reward tokenRewards) public rewardData;
    mapping(address user => mapping(address rewardToken => uint256 rewards)) public claimableRewards;
    mapping(address user => mapping(address rewardToken => uint256 rewards)) public userRewardPerTokenPaid;

    /// @dev For use when migrating to a new staking contract.
    address public migrator;

    struct Reward {
        uint40 periodFinish;
        uint216 rewardRate; // The reward amount (1e18) per total reward duration
        uint40 lastUpdateTime;
        uint216 rewardPerTokenStored;
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS/CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    event RewardAdded(address token, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, address toAddress, uint256 amount);
    event RewardPaid(
        address indexed user,
        address toAddress,
        address rewardToken,
        uint256 reward
    );
    event UpdatedRewardDistributor(address distributor);
    event MigratorSet(address migrator);

    constructor(address _stakingToken, address _distributor) {
        stakingToken = IERC20(_stakingToken);
        rewardDistributor = _distributor;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    // set distributor of rewards
    function setRewardDistributor(address _distributor) external onlyOwner {
        rewardDistributor = _distributor;

        emit UpdatedRewardDistributor(_distributor);
    }

    /// @dev add a new reward token to be distributed
    function addReward(address _rewardToken) external onlyOwner {
        require(rewardData[_rewardToken].lastUpdateTime == 0, "exists");
        rewardTokens.push(_rewardToken);
        rewardData[_rewardToken].lastUpdateTime = uint40(block.timestamp);
        rewardData[_rewardToken].periodFinish = uint40(block.timestamp); // not started
    }

    function setMigrator(address _migrator) external onlyOwner {
        migrator = _migrator;
        emit MigratorSet(_migrator);
    }

    function stakeAll() external {
        uint256 balance = stakingToken.balanceOf(msg.sender);
        stakeFor(msg.sender, balance);
    }

    function stake(uint256 _amount) external {
        stakeFor(msg.sender, _amount);
    }

    /**
     * @notice For migrations to a new staking contract:
     *         1. User/DApp checks if the user has a balance in the `oldStakingContract`
     *         2. If yes, user calls this function `newStakingContract.migrateStake(oldStakingContract, balance)`
     *         3. Staking balances are migrated to the new contract, user will start to earn rewards in the new contract.
     *         4. Any claimable rewards in the old contract are sent directly to the user's wallet.
     * @param oldStaking The old staking contract funds are being migrated from.
     * @param amount The amount to migrate - generally this would be the staker's balance
     */
    function migrateStake(address oldStaking, uint256 amount) external {
        TastyStaking(oldStaking).migrateWithdraw(msg.sender, amount);
        _applyStake(msg.sender, amount);
    }

    function getReward(
        address staker,
        address rewardToken
    ) external updateReward(staker) {
        _getReward(staker, rewardToken, staker);
    }

    /// @dev set the amount of reward to be distributed for a given token & transfer reward tokens
    function notifyRewardAmount(
        address _rewardsToken,
        uint256 _amount
    ) external updateReward(address(0)) {
        require(msg.sender == rewardDistributor, "not distributor");
        require(_amount > 0, "No reward");
        require(
            rewardData[_rewardsToken].lastUpdateTime != 0,
            "unknown reward token"
        );

        _notifyReward(_rewardsToken, _amount);

        IERC20(_rewardsToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        emit RewardAdded(_rewardsToken, _amount);
    }

    /**
     * @notice For migrations to a new staking contract.
     *         1. Withdraw `staker`s tokens to the new staking contract (the migrator)
     *         2. Any existing rewards are claimed and sent directly to the `staker`
     * @dev Called only from the new staking contract (the migrator).
     *      `setMigrator(new_staking_contract)` needs to be called first
     * @param staker The staker who is being migrated to a new staking contract.
     * @param amount The amount to migrate - generally this would be the staker's balance
     */
    function migrateWithdraw(
        address staker,
        uint256 amount
    ) external onlyMigrator {
        _withdrawFor(staker, msg.sender, amount, true, staker);
    }

    function withdrawAll(bool claim) external {
        _withdrawFor(
            msg.sender,
            msg.sender,
            balanceOf[msg.sender],
            claim,
            msg.sender
        );
    }

    function getRewards(address staker) external updateReward(staker) {
        _getRewards(staker, staker);
    }

    function rewardPerToken(
        address _rewardsToken
    ) external view returns (uint256) {
        return _rewardPerToken(_rewardsToken);
    }

    function rewardPeriodFinish(address _token) external view returns (uint40) {
        return rewardData[_token].periodFinish;
    }

    /// @dev calculate amount earned for `_account`
    function earned(
        address _account,
        address _rewardsToken
    ) external view returns (uint256) {
        return _earned(_account, _rewardsToken, balanceOf[_account]);
    }

    /*//////////////////////////////////////////////////////////////
                                 PUBLIC
    //////////////////////////////////////////////////////////////*/

    function stakeFor(address _for, uint256 _amount) public {
        require(_amount > 0, "Cannot stake 0");

        // pull tokens and apply stake
        stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
        _applyStake(_for, _amount);
    }

    function withdraw(uint256 amount, bool claim) public {
        _withdrawFor(msg.sender, msg.sender, amount, claim, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _applyStake(
        address _for,
        uint256 _amount
    ) internal updateReward(_for) {
        totalSupply += _amount;
        balanceOf[_for] += _amount;
        emit Staked(_for, _amount);
    }

    function _withdrawFor(
        address staker,
        address toAddress,
        uint256 amount,
        bool claimRewards,
        address rewardsToAddress
    ) internal updateReward(staker) {
        require(amount > 0, "Cannot withdraw 0");
        require(balanceOf[staker] >= amount, "Not enough staked tokens");

        totalSupply -= amount;
        balanceOf[staker] -= amount;

        stakingToken.safeTransfer(toAddress, amount);
        emit Withdrawn(staker, toAddress, amount);

        if (claimRewards) {
            // can call internal because user reward already updated
            _getRewards(staker, rewardsToAddress);
        }
    }

    // @dev internal function. make sure to call only after updateReward(account)
    function _getRewards(address staker, address rewardsToAddress) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            _getReward(staker, rewardTokens[i], rewardsToAddress);
        }
    }

    function _getReward(
        address staker,
        address rewardToken,
        address rewardsToAddress
    ) internal {
        uint256 amount = claimableRewards[staker][rewardToken];
        if (amount > 0) {
            claimableRewards[staker][rewardToken] = 0;
            IERC20(rewardToken).safeTransfer(rewardsToAddress, amount);

            emit RewardPaid(staker, rewardsToAddress, rewardToken, amount);
        }
    }

    /// @dev set the data for a given `_rewardsToken`
    /// @dev allows adding more rewards to an existing `_rewardsToken` & resetting duration
    function _notifyReward(address _rewardsToken, uint256 _amount) internal {
        Reward storage rdata = rewardData[_rewardsToken];

        if (block.timestamp >= rdata.periodFinish) {
            // new reward token
            rdata.rewardRate = uint216(_amount / DURATION);
        } else {
            // adding to existing reward token
            uint256 remaining = uint256(rdata.periodFinish) - block.timestamp;
            uint256 leftover = remaining * rdata.rewardRate;
            rdata.rewardRate = uint216((_amount + leftover) / DURATION);
        }

        rdata.lastUpdateTime = uint40(block.timestamp); // starts now
        rdata.periodFinish = uint40(block.timestamp + DURATION); // set duration
    }

    /// @dev returns current timestamp if < periodFinish for reward
    /// @param _finishTime timestamp of periodFinish for rewards
    function _lastTimeRewardApplicable(
        uint256 _finishTime
    ) internal view returns (uint256) {
        if (_finishTime < block.timestamp) {
            return _finishTime;
        }
        return block.timestamp;
    }

    /// @dev logic for calculating amount you've earned in total
    function _earned(
        address _account,
        address _rewardsToken,
        uint256 _balance
    ) internal view returns (uint256) {
        return
            (_balance *
                (_rewardPerToken(_rewardsToken) -
                    userRewardPerTokenPaid[_account][_rewardsToken])) /
            1e18 +
            claimableRewards[_account][_rewardsToken];
    }

    /// @dev calculates reward per staked token
    function _rewardPerToken(
        address _rewardsToken
    ) internal view returns (uint256) {
        if (totalSupply == 0) {
            return rewardData[_rewardsToken].rewardPerTokenStored;
        }

        return
            rewardData[_rewardsToken].rewardPerTokenStored +
            (((_lastTimeRewardApplicable(
                rewardData[_rewardsToken].periodFinish
            ) - rewardData[_rewardsToken].lastUpdateTime) *
                rewardData[_rewardsToken].rewardRate *
                1e18) / totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyMigrator() {
        require(msg.sender == migrator, "not migrator");
        _;
    }

    modifier updateReward(address _account) {
        {
            // stack too deep
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                address token = rewardTokens[i];
                rewardData[token].rewardPerTokenStored = uint216(
                    _rewardPerToken(token)
                );
                rewardData[token].lastUpdateTime = uint40(
                    _lastTimeRewardApplicable(rewardData[token].periodFinish)
                );
                if (_account != address(0)) {
                    claimableRewards[_account][token] = _earned(
                        _account,
                        token,
                        balanceOf[_account]
                    );
                    userRewardPerTokenPaid[_account][token] = uint256(
                        rewardData[token].rewardPerTokenStored
                    );
                }
            }
        }
        _;
    }
}
