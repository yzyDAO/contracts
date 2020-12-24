// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMath.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./IYZY.sol";
import "./IUniV2Pair.sol";

contract YZYVault is Context, Ownable {
    using SafeMath for uint256;

    // States
    address private _uniswapV2Pair;
    address private _yzyAddress;
    address private _devAddress;
    address private _yfiPoolAddress;
    address private _wbtcPoolAddress;
    address private _wethPoolAddress;
    uint16 private _devFee;

    // Period of reward distribution to stakers
    // It is `1 days` by default and could be changed
    // later only by Governance
    uint256 private _rewardPeriod;
    uint256 private _maxLockPeriod;
    uint256 private _minLockPeriod;
    bool private _enabledLock;

    // save the timestamp for every period's reward
    uint256 private _lastRewardedTime;
    uint256 private _contractStartTime;
    uint256 private _totalStakedAmount;
    address[] private _stakerList;

    struct StakerInfo {
        uint256 totalStakedAmount;
        uint256 lastWithrewTime;
        uint256 lockedTo;
    }

    mapping(uint256 => uint256) private _eraRewards;
    mapping(uint256 => uint256) private _eraTotalStakedAmounts;
    mapping(uint256 => mapping(address => uint256))
        private _userEraStakedAmounts;
    mapping(address => StakerInfo) private _stakers;

    // Events
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event EnabledLock(address indexed governance);
    event DisabledLock(address indexed governance);
    event ChangedMaximumLockPeriod(address indexed governance, uint256 value);
    event ChangedMinimumLockPeriod(address indexed governance, uint256 value);
    event ChangedRewardPeriod(address indexed governance, uint256 value);
    event ChangedUniswapV2Pair(
        address indexed governance,
        address indexed uniswapV2Pair
    );
    event ChangedYzyAddress(
        address indexed governance,
        address indexed yzyAddress
    );
    event changedDevFeeReciever(
        address indexed governance,
        address indexed oldAddress,
        address indexed newAddress
    );
    event EmergencyWithdrewToken(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event WithdrewReward(address indexed staker, uint256 amount);

    // Modifier

    /**
     * @dev Throws if called by any account other than the YZY token contract.
     */
    modifier onlyYzy() {
        require(
            _yzyAddress == _msgSender(),
            "Ownable: caller is not the YZY token contract"
        );
        _;
    }

    modifier onlyUnlocked() {
        require(
            !isEnabledLock() ||
                (_stakers[_msgSender()].lockedTo > 0 &&
                    block.timestamp >= _stakers[_msgSender()].lockedTo),
            "Staking pool is locked"
        );
        _;
    }

    constructor() {
        _rewardPeriod = 1 days;
        _contractStartTime = block.timestamp;
        _lastRewardedTime = _contractStartTime;
        _devFee = 400;
        _maxLockPeriod = 365 days; // around 1 year
        _minLockPeriod = 90 days; // around 3 months
        _enabledLock = true;
    }

    /**
     * @dev Return value of reward period
     */
    function rewardPeriod() external view returns (uint256) {
        return _rewardPeriod;
    }

    /**
     * @dev Return contract started time
     */
    function contractStartTime() external view returns (uint256) {
        return _contractStartTime;
    }

    /**
     * @dev Enable lock functionality. Call by only Governance.
     */
    function enableLock() external onlyGovernance {
        _enabledLock = true;
        emit EnabledLock(governance());
    }

    /**
     * @dev Disable lock functionality. Call by only Governance.
     */
    function disableLock() external onlyGovernance {
        _enabledLock = false;
        emit DisabledLock(governance());
    }

    /**
     * @dev Disable lock functionality. Call by only Governance.
     */
    function isEnabledLock() public view returns (bool) {
        return _enabledLock;
    }

    /**
     * @dev Return maximum lock period.
     */
    function maximumLockPeriod() external view returns (uint256) {
        return _maxLockPeriod;
    }

    /**
     * @dev Change maximun lock period. Call by only Governance.
     */
    function changedMaximumLockPeriod(uint256 maxLockPeriod_)
        external
        onlyGovernance
    {
        _maxLockPeriod = maxLockPeriod_;
        emit ChangedMaximumLockPeriod(governance(), _maxLockPeriod);
    }

    /**
     * @dev Return minimum lock period.
     */
    function minimumLockPeriod() external view returns (uint256) {
        return _minLockPeriod;
    }

    /**
     * @dev Change minimum lock period. Call by only Governance.
     */
    function changedMinimumLockPeriod(uint256 minLockPeriod_)
        external
        onlyGovernance
    {
        _minLockPeriod = minLockPeriod_;
        emit ChangedMinimumLockPeriod(governance(), _minLockPeriod);
    }

    /**
     * @dev Change value of reward period. Call by only Governance.
     */
    function changeRewardPeriod(uint256 rewardPeriod_) external onlyGovernance {
        _rewardPeriod = rewardPeriod_;
        emit ChangedRewardPeriod(governance(), rewardPeriod_);
    }

    /**
     * @dev Return address of YZY-ETH Uniswap V2 pair
     */
    function uniswapV2Pair() external view returns (address) {
        return _uniswapV2Pair;
    }

    /**
     * @dev Change YZY-ETH Uniswap V2 Pair address. Call by only Governance.
     */
    function changeUniswapV2Pair(address uniswapV2Pair_)
        external
        onlyGovernance
    {
        _uniswapV2Pair = uniswapV2Pair_;
        emit ChangedUniswapV2Pair(governance(), uniswapV2Pair_);
    }

    /**
     * @dev Return address of YZY Token contract
     */
    function yzyAddress() external view returns (address) {
        return _yzyAddress;
    }

    /**
     * @dev Change YZY Token contract address. Call by only Governance.
     */
    function changeYzyAddress(address yzyAddress_) external onlyGovernance {
        _yzyAddress = yzyAddress_;
        emit ChangedYzyAddress(governance(), yzyAddress_);
    }

    /**
     * @dev Return address of dev fee receiver
     */
    function devFeeReciever() external view returns (address) {
        return _devAddress;
    }

    /**
     * @dev Update dev address by the previous dev.
     * Note onlyOwner functions are meant for the governance contract
     * allowing YZY governance token holders to do this functions.
     */
    function changeDevFeeReciever(address devAddress_) external onlyGovernance {
        address oldAddress = _devAddress;
        _devAddress = devAddress_;
        emit changedDevFeeReciever(governance(), oldAddress, _devAddress);
    }

    /**
     * @dev Return dev fee
     */
    function devFee() external view returns (uint16) {
        return _devFee;
    }

    /**
     * @dev Update the dev fee for this contract
     * defaults at 4.00%
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeDevFee(uint16 devFee_) external onlyGovernance {
        require(_devFee <= 1000, "Dev fee clamped at 10%");
        _devFee = devFee_;
    }

    /**
     * @dev Return the number of stakers
     */
    function numberOfStakers() external view returns (uint256) {
        return _stakerList.length;
    }

    /**
     * @dev Add fee to era reward variable
     * Note Call by only YZY token contract
     */
    function addEraReward(uint256 amount_) external onlyYzy returns (bool) {
        uint256 blockTime = block.timestamp;

        if (blockTime.sub(_lastRewardedTime) >= _rewardPeriod) {
            uint256 currentTime = _lastRewardedTime.add(_rewardPeriod);
            _eraRewards[currentTime] = _eraRewards[currentTime].add(amount_);
            _lastRewardedTime = currentTime;
        } else {
            _eraRewards[_lastRewardedTime] = _eraRewards[_lastRewardedTime].add(
                amount_
            );
        }

        return true;
    }

    /**
     * @dev Stake YZY-ETH LP tokens
     */
    function stake(uint256 amount_, uint256 lockTime) external {
        require(!_isContract(_msgSender()), "Could not be a contract");
        require(amount_ > 0, "Staking amount must be more than zero");
        require(
            lockTime <= _maxLockPeriod && lockTime >= _minLockPeriod,
            "Invalid lock time"
        );

        // Transfer tokens from staker to the contract amount
        require(
            IUniV2Pair(_uniswapV2Pair).transferFrom(
                _msgSender(),
                address(this),
                amount_
            ),
            "It has failed to transfer tokens from staker to contract."
        );

        // Increase the total staked amount
        _totalStakedAmount = _totalStakedAmount.add(amount_);

        // Increase era staked amount
        _eraTotalStakedAmounts[_lastRewardedTime] = _eraTotalStakedAmounts[
            _lastRewardedTime
        ]
            .add(amount_);

        if (_stakers[_msgSender()].lastWithrewTime == 0) {
            _stakers[_msgSender()].lastWithrewTime = _lastRewardedTime;
            _stakers[_msgSender()].lockedTo = lockTime.add(block.timestamp);
            _stakerList.push(_msgSender());
        }

        // Increase staked amount of the staker
        _userEraStakedAmounts[_lastRewardedTime][
            _msgSender()
        ] = _userEraStakedAmounts[_lastRewardedTime][_msgSender()].add(amount_);
        _stakers[_msgSender()].totalStakedAmount = _stakers[_msgSender()]
            .totalStakedAmount
            .add(amount_);

        emit Staked(_msgSender(), amount_);
    }

    /**
     * @dev Unstake staked YZY-ETH LP tokens
     */
    function unstake() external onlyUnlocked {
        require(!_isContract(_msgSender()), "Could not be a contract");
        uint256 amount = _stakers[_msgSender()].totalStakedAmount;
        require(amount > 0, "No running stake");

        _withdrawReward();

        // Decrease the total staked amount
        _totalStakedAmount = _totalStakedAmount.sub(amount);
        _stakers[_msgSender()].totalStakedAmount = 0;

        // Decrease the staker's amount
        uint256 blockTime = block.timestamp;
        uint256 lastWithrewTime = _stakers[_msgSender()].lastWithrewTime;
        uint256 n = blockTime.sub(lastWithrewTime).div(_rewardPeriod);

        for (uint256 i = 0; i < n; i++) {
            uint256 rewardTime = lastWithrewTime.add(_rewardPeriod.mul(i));
            if (_userEraStakedAmounts[rewardTime][_msgSender()] != 0) {
                _userEraStakedAmounts[rewardTime][_msgSender()] = 0;
            }
        }
        // Initialize started time of user
        _stakers[_msgSender()].lastWithrewTime = 0;

        for (uint256 i = 0; i < _stakerList.length; i++) {
            if (_stakerList[i] == _msgSender()) {
                _stakerList[i] = _stakerList[_stakerList.length - 1];
                _stakerList.pop();
                break;
            }
        }

        // Transfer LP tokens from contract to staker
        require(
            IUniV2Pair(_uniswapV2Pair).transfer(_msgSender(), amount),
            "It has failed to transfer tokens from contract to staker."
        );

        emit Unstaked(_msgSender(), amount);
    }

    /**
     * @dev API to get staker's reward
     */
    function getReward(address account_)
        public
        view
        returns (uint256, uint256)
    {
        require(!_isContract(account_), "Could not be a contract");

        uint256 reward = 0;
        uint256 blockTime = block.timestamp;
        uint256 lastWithrewTime = _stakers[account_].lastWithrewTime;

        if (lastWithrewTime > 0) {
            uint256 n = blockTime.sub(lastWithrewTime).div(_rewardPeriod);

            for (uint256 i = 1; i <= n; i++) {
                lastWithrewTime = lastWithrewTime.add(_rewardPeriod.mul(i));
                uint256 eraRewards = _eraRewards[lastWithrewTime];
                uint256 eraTotalStakedAmounts =
                    _eraTotalStakedAmounts[lastWithrewTime];
                uint256 stakedAmount =
                    _userEraStakedAmounts[lastWithrewTime][account_];
                reward = stakedAmount
                    .mul(eraRewards)
                    .div(eraTotalStakedAmounts)
                    .add(reward);
            }
        }

        return (reward, lastWithrewTime);
    }

    /**
     * @dev API to withdraw rewards to staker's wallet
     */
    function withdrawReward() external returns (bool) {
        _withdrawReward();
        return true;
    }

    /**
     * @dev API to get the last rewarded time
     */
    function lastRewardedTime() external view returns (uint256) {
        return _lastRewardedTime;
    }

    /**
     * @dev API to get the era rewards
     */
    function eraReward(uint256 era_) external view returns (uint256) {
        return _eraRewards[era_];
    }

    /**
     * @dev API to get the total staked amount of all stakers
     */
    function totalStakedAmount() external view returns (uint256) {
        return _totalStakedAmount;
    }

    /**
     * @dev API to get the total era staked amount of all stakers
     */
    function eraTotalStakedAmount(uint256 era_)
        external
        view
        returns (uint256)
    {
        return _eraTotalStakedAmounts[era_];
    }

    /**
     * @dev API to get the staker's staked amount
     */
    function userTotalStakedAmount(address account_)
        external
        view
        returns (uint256)
    {
        return _stakers[account_].totalStakedAmount;
    }

    /**
     * @dev API to get the staker's staked amount
     */
    function userEraStakedAmount(uint256 era_, address account_)
        external
        view
        returns (uint256)
    {
        return _userEraStakedAmounts[era_][account_];
    }

    /**
     * @dev API to get the staker's started time the staking
     */
    function userLastWithrewTime(address account_)
        external
        view
        returns (uint256)
    {
        return _stakers[account_].lastWithrewTime;
    }

    /**
     * @dev API to get the staker's rank
     */
    function userRank(address account_) external view returns (uint256) {
        require(account_ != address(0), "Invalid address");

        uint256 rank = 1;
        uint256 userStakedAmount = _stakers[account_].totalStakedAmount;

        for (uint256 i = 0; i < _stakerList.length; i++) {
            address staker = _stakerList[i];
            if (
                staker != account_ &&
                userStakedAmount < _stakers[staker].totalStakedAmount
            ) rank = rank.add(1);
        }
        return rank;
    }

    /**
     * @dev API to get locked timestamp of the staker
     */
    function userLockedTo(address account_) external view returns (uint256) {
        require(account_ != address(0), "Invalid address");
        return _stakers[account_].lockedTo;
    }

    /**
     * @dev Withdraw YZY token from vault wallet to owner when only emergency!
     *
     */
    function emergencyWithdrawToken() external onlyGovernance {
        require(_msgSender() != address(0), "Invalid address");

        uint256 tokenAmount = IYZY(_yzyAddress).balanceOf(address(this));
        require(tokenAmount > 0, "Insufficient amount");

        IYZY(_yzyAddress).transferWithoutFee(_msgSender(), tokenAmount);
        emit EmergencyWithdrewToken(address(this), _msgSender(), tokenAmount);
    }

    /**
     * @dev Low level withdraw internal function
     */
    function _withdrawReward() internal {
        (uint256 rewards, uint256 lastWithrewTime) = getReward(_msgSender());

        require(rewards > 0, "No reward state");

        uint256 devFeeAmount = rewards.mul(uint256(_devFee)).div(10000);
        uint256 actualRewards = rewards.sub(devFeeAmount);

        // Transfer reward tokens from contract to staker
        require(
            IYZY(_yzyAddress).transferWithoutFee(_msgSender(), actualRewards),
            "It has failed to transfer tokens from contract to staker."
        );

        // Transfer devFee tokens from contract to devAddress
        require(
            IYZY(_yzyAddress).transferWithoutFee(_devAddress, devFeeAmount),
            "It has failed to transfer tokens from contract to dev address."
        );

        // update user's last withrew time
        _stakers[_msgSender()].lastWithrewTime = lastWithrewTime;

        emit WithdrewReward(_msgSender(), rewards);
    }

    /**
     * @dev Internal function if address is contract
     */
    function _isContract(address address_) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(address_)
        }
        return size > 0;
    }
}
