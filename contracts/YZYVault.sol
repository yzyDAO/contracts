// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMath.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./IYZY.sol";
import "./IERC20.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Router02.sol";

contract YZYVault is Context, Ownable {
    using SafeMath for uint256;

    // States
    address private _uniswapV2Pair;
    address private _yzyAddress;
    address private _devAddress;
    address private _yfiTokenAddress;
    address private _wbtcTokenAddress;
    address private _wethTokenAddress;

    uint16 private _treasuryFee;
    uint16 private _devFee;
    uint16 private _quarterlyFee;
    uint16 private _buyingYFITokenFee;
    uint16 private _buyingWBTCTokenFee;
    uint16 private _buyingWETHTokenFee;
    uint16 private _burnFee;

    IUniswapV2Router02 private _uniswapV2Router;

    // Period of reward distribution to stakers
    // It is `1 days` by default and could be changed
    // later only by Governance
    uint256 private _treasuryRewardPeriod;
    uint256 private _quarterlyRewardPeriod;
    uint256 private _maxLockPeriod;
    uint256 private _minLockPeriod;
    uint256 private _minDepositETHAmount;
    bool private _enabledLock;

    // save the timestamp for every period's reward
    uint256 private _contractStartTime;
    uint256 private _totalStakedAmount;
    address[] private _stakerList;

    // variables for block rewards
    uint256 private _initialBlockNum;
    uint256 private _treasuryFirstRewardBlockCount;
    uint256 private _treasuryFirstRewardEndedBlockNum;
    uint256 private _quarterlyFirstRewardBlockCount;
    uint256 private _quarterlyFirstRewardEndedBlockNum;
    uint256 private _yearlyRewardBlockCount;
    uint256 private _yearlyRewardEndedBlockNum;
    uint256 private _oneBlockTime;
    uint256 private _initialFirstTreasuryReward;
    uint256 private _initialFirstQuarterlyReward;
    uint256 private _initialYearlyTreasuryReward;
    uint256 private _initialYearlyQuarterlyReward;

    mapping(uint256 => uint256) private _blockTreasuryRewards;
    mapping(uint256 => uint256) private _blockQuarterlyRewards;

    struct StakerInfo {
        uint256 totalStakedAmount;
        uint256 lastTreasuryRewardBlockNum;
        uint256 lastQuarterlyRewardBlockNum;
        uint256 lastUnStakedBlockNum;
        uint256 lockedTo;
    }

    struct BlockStakedInfo {
        uint256 blockNum;
        uint256 stakedAmount;
    }

    BlockStakedInfo[] private _totalStakedList;
    mapping(address => BlockStakedInfo[]) private _stakerInfoList;

    mapping(address => StakerInfo) private _stakers;

    // Events
    event Staked(address indexed account, uint256 amount);
    event LPStaked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event EnabledLock(address indexed governance);
    event DisabledLock(address indexed governance);
    event ChangedMaximumLockPeriod(address indexed governance, uint256 value);
    event ChangedMinimumLockPeriod(address indexed governance, uint256 value);
    event ChangedMinimumETHDepositAmount(
        address indexed governance,
        uint256 value
    );
    event ChangedTreasuryRewardPeriod(
        address indexed governance,
        uint256 value
    );
    event ChangeQuarterlyRewardPeriod(
        address indexed governance,
        uint256 value
    );
    event ChangedUniswapV2Pair(
        address indexed governance,
        address indexed uniswapV2Pair
    );
    event ChangedUniswapV2Router(
        address indexed governance,
        address indexed uniswapV2Pair
    );
    event ChangedYzyAddress(
        address indexed governance,
        address indexed yzyAddress
    );
    event ChangedYfiTokenAddress(
        address indexed governance,
        address indexed yfiAddress
    );
    event ChangedWbtcTokenAddress(
        address indexed governance,
        address indexed wbtcAddress
    );
    event ChangedWethTokenAddress(
        address indexed governance,
        address indexed wethAddress
    );
    event ChangedDevFeeReciever(
        address indexed governance,
        address indexed oldAddress,
        address indexed newAddress
    );
    event EmergencyWithdrawToken(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event WithdrawTreasuryReward(address indexed staker, uint256 amount);
    event WithdrawQuarterlyReward(address indexed staker, uint256 amount);
    event ChangeTreasuryFee(address indexed governance, uint16 value);
    event ChangeDevFee(address indexed governance, uint16 value);
    event ChangeQuarterlyFee(address indexed governance, uint16 value);
    event ChangeBuyingYFITokenFee(address indexed governance, uint16 value);
    event ChangeBuyingWBTCTokenFee(address indexed governance, uint16 value);
    event ChangeBuyingWETHTokenFee(address indexed governance, uint16 value);
    event ChangeBurnFee(address indexed governance, uint16 value);
    event SwapAndLiquifyForYZY(
        address indexed msgSender,
        uint256 totAmount,
        uint256 ethAmount,
        uint256 yzyAmount
    );

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

    constructor(address uniswapV2Router) {
        _uniswapV2Router = IUniswapV2Router02(uniswapV2Router);

        _treasuryRewardPeriod = 14 days;
        _quarterlyRewardPeriod = 90 days;
        _contractStartTime = block.timestamp;

        _treasuryFee = 7600; // 76% of taxFee to treasuryFee
        _devFee = 400; // 4% of taxFee to devFee
        _quarterlyFee = 2000; // 20% of taxFee to buyingTokenFee
        _buyingYFITokenFee = 5000; // 50% of buyingTokenFee to buy YFI token
        _buyingWBTCTokenFee = 3000; // 30% of buyingTokenFee to buy WBTC token
        _buyingWETHTokenFee = 2000; // 20% of buyingTokenFee to buy WETH token
        _burnFee = 2000; // 20% of pending reward to burn when staker request to withdraw pending reward

        _minDepositETHAmount = 1E17;
        _maxLockPeriod = 365 days; // around 1 year
        _minLockPeriod = 90 days; // around 3 months
        _enabledLock = true;

        // Initialize Block Infos
        _oneBlockTime = 14; // 14 seconds
        _initialBlockNum = block.number;
        _yearlyRewardBlockCount = (uint256)(365 days).div(_oneBlockTime);
        _yearlyRewardEndedBlockNum = _initialBlockNum.add(
            _yearlyRewardBlockCount
        );

        // Initialize Treasury Rewards Infos
        _treasuryFirstRewardBlockCount = _treasuryRewardPeriod.div(
            _oneBlockTime
        );
        _treasuryFirstRewardEndedBlockNum = _initialBlockNum.add(
            _treasuryFirstRewardBlockCount
        );

        // Initialize Quarterly Rewards Infos
        _quarterlyFirstRewardBlockCount = _quarterlyRewardPeriod.div(
            _oneBlockTime
        );
        _quarterlyFirstRewardEndedBlockNum = _initialBlockNum.add(
            _quarterlyFirstRewardBlockCount
        );

        // Initialize the reward amount
        _initialFirstTreasuryReward = (uint256)(2000E18)
            .mul((uint256)(_treasuryFee).add(_devFee))
            .div(10000)
            .div(_treasuryFirstRewardBlockCount);

        _initialFirstQuarterlyReward = (uint256)(2000E18)
            .sub(
            _initialFirstTreasuryReward.mul(_treasuryFirstRewardBlockCount)
        )
            .div(_quarterlyFirstRewardBlockCount);

        _initialYearlyTreasuryReward = (uint256)(7900E18)
            .mul((uint256)(_treasuryFee).add(_devFee))
            .div(10000)
            .div(_yearlyRewardBlockCount);

        _initialYearlyQuarterlyReward = (uint256)(7900E18)
            .sub(_initialYearlyTreasuryReward.mul(_yearlyRewardBlockCount))
            .div(_yearlyRewardBlockCount);

        _totalStakedList.push(BlockStakedInfo(_initialBlockNum, 0));
    }

    /**
     * @dev Return Staker Info
     */
    function getStakerInfo(address staker)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            _stakers[staker].totalStakedAmount,
            _stakers[staker].lastTreasuryRewardBlockNum,
            _stakers[staker].lastQuarterlyRewardBlockNum,
            _stakers[staker].lastUnStakedBlockNum,
            _stakers[staker].lockedTo
        );
    }

    /**
     * @dev Return Total Staked Length
     */
    function getTotalStakedLength() external view returns (uint256) {
        return _totalStakedList.length;
    }

    /**
     * @dev Return Total Staked Info
     */
    function getTotalStakedInfo(uint256 step)
        external
        view
        returns (uint256, uint256)
    {
        return (
            _totalStakedList[step].blockNum,
            _totalStakedList[step].stakedAmount
        );
    }

    /**
     * @dev Return User Staked Length
     */
    function getUserStakedLength(address staker)
        external
        view
        returns (uint256)
    {
        return _stakerInfoList[staker].length;
    }

    /**
     * @dev Return User Staked Info
     */
    function getUserStakedInfo(address staker, uint256 step)
        external
        view
        returns (uint256, uint256)
    {
        return (
            _stakerInfoList[staker][step].blockNum,
            _stakerInfoList[staker][step].stakedAmount
        );
    }

    /**
     * @dev Return minium Deposit ETH Amount
     */
    function minimumDepositETHAmount() external view returns (uint256) {
        return _minDepositETHAmount;
    }

    /**
     * @dev Change Minimum Deposit ETH Amount. Call by only Governance.
     */
    function changeMinimumDepositETHAmount(uint256 minDepositETHAmount_)
        external
        onlyGovernance
    {
        _minDepositETHAmount = minDepositETHAmount_;
        emit ChangedMinimumETHDepositAmount(governance(), minDepositETHAmount_);
    }

    /**
     * @dev Return address of YFI Token contract
     */
    function yfiTokenAddress() external view returns (address) {
        return _yfiTokenAddress;
    }

    /**
     * @dev Change YFI Token contract address. Call by only Governance.
     */
    function changeYfiTokenAddress(address yfiAddress_)
        external
        onlyGovernance
    {
        _yfiTokenAddress = yfiAddress_;
        emit ChangedYfiTokenAddress(governance(), yfiAddress_);
    }

    /**
     * @dev Return address of WBTC Token contract
     */
    function wbtcTokenAddress() external view returns (address) {
        return _wbtcTokenAddress;
    }

    /**
     * @dev Change WBTC Token address. Call by only Governance.
     */
    function changeWbtcTokenAddress(address wbtcAddress_)
        external
        onlyGovernance
    {
        _wbtcTokenAddress = wbtcAddress_;
        emit ChangedWbtcTokenAddress(governance(), wbtcAddress_);
    }

    /**
     * @dev Return address of WETH Token contract
     */
    function wethTokenAddress() external view returns (address) {
        return _wethTokenAddress;
    }

    /**
     * @dev Change WETH Token address. Call by only Governance.
     */
    function changeWethTokenAddress(address wethAddress_)
        external
        onlyGovernance
    {
        _wethTokenAddress = wethAddress_;
        emit ChangedWethTokenAddress(governance(), wethAddress_);
    }

    /**
     * @dev Return value of treasury reward period
     */
    function treasuryRewardPeriod() external view returns (uint256) {
        return _treasuryRewardPeriod;
    }

    /**
     * @dev Change value of treasury reward period. Call by only Governance.
     */
    function changeTreasuryRewardPeriod(uint256 treasuryRewardPeriod_)
        external
        onlyGovernance
    {
        _treasuryRewardPeriod = treasuryRewardPeriod_;
        emit ChangedTreasuryRewardPeriod(governance(), treasuryRewardPeriod_);
    }

    /**
     * @dev Return value of quarterly reward period
     */
    function quarterlyRewardPeriod() external view returns (uint256) {
        return _quarterlyRewardPeriod;
    }

    /**
     * @dev Change value of quarterly reward period. Call by only Governance.
     */
    function changeQuarterlyRewardPeriod(uint256 quarterlyRewardPeriod_)
        external
        onlyGovernance
    {
        _quarterlyRewardPeriod = quarterlyRewardPeriod_;
        emit ChangeQuarterlyRewardPeriod(governance(), quarterlyRewardPeriod_);
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
     * @dev Return address of Uniswap V2Router
     */
    function uniswapV2Router() external view returns (address) {
        return address(_uniswapV2Router);
    }

    /**
     * @dev Change address of Uniswap V2Router. Call by only Governance.
     */
    function changeUniswapV2Router(address uniswapV2Router_)
        external
        onlyGovernance
    {
        _uniswapV2Router = IUniswapV2Router02(uniswapV2Router_);
        emit ChangedUniswapV2Router(governance(), address(uniswapV2Router_));
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
     * Note onlyGovernance functions are meant for the governance contract
     * allowing YZY governance token holders to do this functions.
     */
    function changeDevFeeReciever(address devAddress_) external onlyGovernance {
        address oldAddress = _devAddress;
        _devAddress = devAddress_;
        emit ChangedDevFeeReciever(governance(), oldAddress, _devAddress);
    }

    /**
     * @dev Return Treasury fee
     */
    function treasuryFee() external view returns (uint16) {
        return _treasuryFee;
    }

    /**
     * @dev Update the treasury fee for this contract
     * defaults at 76.00% of taxFee, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeTreasuryFee(uint16 treasuryFee_) external onlyGovernance {
        _treasuryFee = treasuryFee_;
        emit ChangeTreasuryFee(governance(), treasuryFee_);
    }

    /**
     * @dev Return Burn fee
     */
    function burnFee() external view returns (uint16) {
        return _burnFee;
    }

    /**
     * @dev Update the burn fee for this contract
     * defaults at 20.00% of Pending Reward Amount, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBurnFee(uint16 burnFee_) external onlyGovernance {
        _burnFee = burnFee_;
        emit ChangeBurnFee(governance(), burnFee_);
    }

    /**
     * @dev Return dev fee
     */
    function devFee() external view returns (uint16) {
        return _devFee;
    }

    /**
     * @dev Update the dev fee for this contract
     * defaults at 4.00% of taxFee, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeDevFee(uint16 devFee_) external onlyGovernance {
        _devFee = devFee_;
        emit ChangeDevFee(governance(), devFee_);
    }

    /**
     * @dev Return Quarterly fee
     */
    function quarterlyFee() external view returns (uint16) {
        return _quarterlyFee;
    }

    /**
     * @dev Update the Quarterly fee for this contract
     * defaults at 20.00% of taxFee, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeQuarterlyFee(uint16 quarterlyFee_) external onlyGovernance {
        _quarterlyFee = quarterlyFee_;
        emit ChangeQuarterlyFee(governance(), quarterlyFee_);
    }

    /**
     * @dev Return BuyingYFIToken fee
     */
    function buyingYFITokenFee() external view returns (uint16) {
        return _buyingYFITokenFee;
    }

    /**
     * @dev Update the buying YFI token fee for this contract
     * defaults at 50.00% of buyingTokenFee
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBuyingYFITokenFee(uint16 buyingYFITokenFee_)
        external
        onlyGovernance
    {
        _buyingYFITokenFee = buyingYFITokenFee_;
        emit ChangeBuyingYFITokenFee(governance(), buyingYFITokenFee_);
    }

    /**
     * @dev Return BuyingWBTCToken fee
     */
    function buyingWBTCTokenFee() external view returns (uint16) {
        return _buyingWBTCTokenFee;
    }

    /**
     * @dev Update the buying WBTC token fee for this contract
     * defaults at 30.00% of buyingTokenFee
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBuyingWBTCTokenFee(uint16 buyingWBTCTokenFee_)
        external
        onlyGovernance
    {
        _buyingWBTCTokenFee = buyingWBTCTokenFee_;
        emit ChangeBuyingWBTCTokenFee(governance(), buyingWBTCTokenFee_);
    }

    /**
     * @dev Return BuyingWETHToken fee
     */
    function buyingWETHTokenFee() external view returns (uint16) {
        return _buyingWETHTokenFee;
    }

    /**
     * @dev Update the buying WETH token fee for this contract
     * defaults at 20.00% of buyingTokenFee
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBuyingWETHTokenFee(uint16 buyingWETHTokenFee_)
        external
        onlyGovernance
    {
        _buyingWETHTokenFee = buyingWETHTokenFee_;
        emit ChangeBuyingWETHTokenFee(governance(), buyingWETHTokenFee_);
    }

    /**
     * @dev Return the number of stakers
     */
    function numberOfStakers() external view returns (uint256) {
        return _stakerList.length;
    }

    /**
     * @dev get last era time
     */
    function _getLastEraTime(
        uint256 lastUpdateTime,
        uint256 currentTime,
        uint256 periodTime
    ) internal pure returns (uint256) {
        require(
            lastUpdateTime < currentTime,
            "Current Time should be more than last update time."
        );

        uint256 n = currentTime.sub(lastUpdateTime).div(periodTime);
        uint256 lastEraTime = lastUpdateTime.add(periodTime.mul(n));

        return lastEraTime;
    }

    /**
     * @dev Get Initial Treasury Block Reward
     */
    function _getInitialTreasuryBlockReward(uint256 currentBlockNum)
        internal
        view
        returns (uint256)
    {
        uint256 currrentTreasuryBlockReward = 0;

        if (currentBlockNum > _initialBlockNum) {
            // if Current Block Number is in Treasury First Reward Period
            if (currentBlockNum <= _treasuryFirstRewardEndedBlockNum) {
                currrentTreasuryBlockReward = _initialFirstTreasuryReward;
            } else {
                // if Current Block Number is in Yearly Reward Period but should pass Weekly Reward Period
                if (currentBlockNum <= _yearlyRewardEndedBlockNum) {
                    currrentTreasuryBlockReward = _initialYearlyTreasuryReward;
                }
            }
        }

        return currrentTreasuryBlockReward;
    }

    /**
     * @dev Get Initial Quarterly Block Reward
     */
    function _getInitialQuarterlyBlockReward(uint256 currentBlockNum)
        internal
        view
        returns (uint256)
    {
        uint256 currrentQuarterlyBlockReward = 0;

        if (currentBlockNum > _initialBlockNum) {
            // if Current Block Number is in Quarterly First Reward Period
            if (currentBlockNum <= _quarterlyFirstRewardEndedBlockNum) {
                currrentQuarterlyBlockReward = _initialFirstQuarterlyReward;
            } else {
                // if Current Block Number is in Yearly Reward Period but should pass Weekly Reward Period
                if (currentBlockNum <= _yearlyRewardEndedBlockNum) {
                    currrentQuarterlyBlockReward = _initialYearlyQuarterlyReward;
                }
            }
        }

        return currrentQuarterlyBlockReward;
    }

    /**
     * @dev API to Get Treasury Block Reward
     */
    function getTreasuryBlockReward(uint256 currentBlockNum)
        external
        view
        returns (uint256)
    {
        uint256 blockTreasuryReward = _blockTreasuryRewards[currentBlockNum];
        if (blockTreasuryReward == 0) {
            blockTreasuryReward = _getInitialTreasuryBlockReward(
                currentBlockNum
            );
        }

        return blockTreasuryReward;
    }

    /**
     * @dev API to Get  Quarterly Block Reward
     */
    function getQuarterlyBlockReward(uint256 currentBlockNum)
        external
        view
        returns (uint256)
    {
        uint256 blockQuarterlyReward = _blockQuarterlyRewards[currentBlockNum];
        if (blockQuarterlyReward == 0) {
            blockQuarterlyReward = _getInitialQuarterlyBlockReward(
                currentBlockNum
            );
        }

        return blockQuarterlyReward;
    }

    /**
     * @dev get last total staked block info
     */
    function _getLastTotalStakedBlockNumber() internal view returns (uint256) {
        uint256 totalStakedListLength = _totalStakedList.length;

        require(
            totalStakedListLength > 0,
            "To get last block info, the length should be more than zero."
        );

        return _totalStakedList[totalStakedListLength - 1].blockNum;
    }

    /**
     * @dev update last total staked block info
     */
    function _updateLastTotalStakedBlockInfo(uint256 newAmount) internal {
        uint256 totalStakedListLength = _totalStakedList.length;

        require(
            totalStakedListLength > 0,
            "To update last block info, the length should be more than zero."
        );

        _totalStakedList[totalStakedListLength - 1].stakedAmount = newAmount;
    }

    /**
     * @dev get last user's staked block info
     */
    function _getLastUserStakedBlockNumber(address stakerAddress)
        internal
        view
        returns (uint256)
    {
        uint256 userStakedListLength = _stakerInfoList[stakerAddress].length;

        require(
            userStakedListLength > 0,
            "To get last block info, the length should be more than zero."
        );

        return
            _stakerInfoList[stakerAddress][userStakedListLength - 1].blockNum;
    }

    /**
     * @dev get last user's staked block info
     */
    function _updateLastUserStakedBlockInfo(
        address stakerAddress,
        uint256 newAmount
    ) internal {
        uint256 userStakedListLength = _stakerInfoList[stakerAddress].length;

        require(
            userStakedListLength > 0,
            "To update last block info, the length should be more than zero."
        );

        _stakerInfoList[stakerAddress][userStakedListLength - 1]
            .stakedAmount = newAmount;
    }

    /**
     * @dev Add fee to era reward variable
     * Note Call by only YZY token contract
     */
    function addEraReward(uint256 amount_) external onlyYzy returns (bool) {
        uint256 currentBlockNum = block.number;
        uint256 treasuryDevFee = uint256(_treasuryFee).add(uint256(_devFee));
        uint256 treasuryRewardAmount = amount_.mul(treasuryDevFee).div(10000);
        uint256 quarterlyRewardAmount = amount_.sub(treasuryRewardAmount);

        require(
            treasuryRewardAmount > 0,
            "Treasure Reward Amount must be more than Zero"
        );
        require(
            quarterlyRewardAmount > 0,
            "Quarterly Reward Amount must be more than Zero"
        );

        // Update Treasury Rewards
        if (_blockTreasuryRewards[currentBlockNum] == 0) {
            uint256 initialBlockReward =
                _getInitialTreasuryBlockReward(currentBlockNum);
            _blockTreasuryRewards[currentBlockNum] = initialBlockReward.add(
                treasuryRewardAmount
            );
        } else {
            _blockTreasuryRewards[currentBlockNum] = _blockTreasuryRewards[
                currentBlockNum
            ]
                .add(treasuryRewardAmount);
        }

        // Update Quarterly Rewards
        if (_blockQuarterlyRewards[currentBlockNum] == 0) {
            uint256 initialBlockReward =
                _getInitialQuarterlyBlockReward(currentBlockNum);
            _blockQuarterlyRewards[currentBlockNum] = initialBlockReward.add(
                quarterlyRewardAmount
            );
        } else {
            _blockQuarterlyRewards[currentBlockNum] = _blockQuarterlyRewards[
                currentBlockNum
            ]
                .add(quarterlyRewardAmount);
        }

        return true;
    }

    function swapETHForTokens(uint256 ethAmount) private {
        // generate the uniswap pair path of weth -> yzy
        address[] memory path = new address[](2);
        path[0] = _uniswapV2Router.WETH();
        path[1] = _yzyAddress;

        // make the swap
        _uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: ethAmount
        }(0, path, address(this), block.timestamp);
    }

    function addLiquidityForEth(uint256 tokenAmount, uint256 ethAmount)
        private
    {
        IYZY(_yzyAddress).approve(address(_uniswapV2Router), tokenAmount);

        // add the liquidity
        _uniswapV2Router.addLiquidityETH{value: ethAmount}(
            _yzyAddress,
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function swapAndLiquifyForYZY(uint256 amount) private returns (bool) {
        uint256 halfForEth = amount.div(2);
        uint256 otherHalfForYZY = amount.sub(halfForEth);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = IYZY(_yzyAddress).balanceOf(address(this));

        // swap ETH for tokens
        swapETHForTokens(otherHalfForYZY);

        // how much YZY did we just swap into?
        uint256 newBalance =
            IYZY(_yzyAddress).balanceOf(address(this)).sub(initialBalance);

        // add liquidity to uniswap
        addLiquidityForEth(newBalance, halfForEth);

        emit SwapAndLiquifyForYZY(_msgSender(), amount, halfForEth, newBalance);

        return true;
    }

    function swapTokensForTokens(
        address fromTokenAddress,
        address toTokenAddress,
        uint256 tokenAmount,
        address receivedAddress
    ) private returns (bool) {
        address[] memory path = new address[](2);
        path[0] = fromTokenAddress;
        path[1] = toTokenAddress;

        IERC20(fromTokenAddress).approve(
            address(_uniswapV2Router),
            tokenAmount
        );

        // make the swap
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of pair token
            path,
            receivedAddress,
            block.timestamp
        );

        return true;
    }

    function getEstimatedSwapTokenAmount(
        address pairIn,
        address pairOut,
        uint256 inAmount
    ) external view returns (uint256[] memory) {
        address[] memory uniswapPairPath = new address[](2);
        uniswapPairPath[0] = pairOut;
        uniswapPairPath[1] = pairIn;

        return _uniswapV2Router.getAmountsIn(inAmount, uniswapPairPath);
    }

    receive() external payable {}

    function stake(uint256 lockTime) external payable {
        uint256 amount_ = msg.value;

        require(!_isContract(_msgSender()), "Could not be a contract");
        require(
            amount_ >= _minDepositETHAmount,
            "ETH Staking amount must be more than min Deposit Amount."
        );
        require(
            lockTime <= _maxLockPeriod && lockTime >= _minLockPeriod,
            "Invalid lock time"
        );

        _stake(amount_, lockTime);
    }

    /**
     * @dev Update Total Stake & User Stake Infos
     */
    function _updateStakeInfo(uint256 newAmount, uint256 lockTime) internal {
        uint256 currentBlockNum = block.number;
        // Increase the total staked amount
        _totalStakedAmount = _totalStakedAmount.add(newAmount);

        // Update Total Block Stacked Info
        uint256 lastTotalStakedBlockNum = _getLastTotalStakedBlockNumber();
        if (lastTotalStakedBlockNum == currentBlockNum) {
            // If Current Block Number is Last Staked Block Number, Update It
            _updateLastTotalStakedBlockInfo(_totalStakedAmount);
        } else {
            // If New, Add New Block Staked Info
            _totalStakedList.push(
                BlockStakedInfo(currentBlockNum, _totalStakedAmount)
            );
        }

        // Update Staker's Locked Time
        if (_stakers[_msgSender()].lockedTo == 0) {
            _stakers[_msgSender()].lockedTo = lockTime.add(block.timestamp);
            _stakerList.push(_msgSender());
        }

        // Update Staker's Initial Info
        if (_stakers[_msgSender()].totalStakedAmount == 0) {
            // If User Stakes at first time
            if (_stakers[_msgSender()].lastUnStakedBlockNum == 0) {
                // Initialize Staker's Treasury Reward Block Number
                _stakers[_msgSender()]
                    .lastTreasuryRewardBlockNum = _initialBlockNum;
                // Initialize Staker's Quarterly Reward Block Number
                _stakers[_msgSender()]
                    .lastQuarterlyRewardBlockNum = _initialBlockNum;
                // Initialize Staker's Block Staked Info
                _stakerInfoList[_msgSender()].push(
                    BlockStakedInfo(_initialBlockNum, 0)
                );
            } else {
                // If User Restakes
                // Initialize Staker's Block Staked Info
                _stakerInfoList[_msgSender()].push(
                    BlockStakedInfo(
                        _stakers[_msgSender()].lastUnStakedBlockNum,
                        0
                    )
                );
            }
        }

        // Increase staked amount of the staker
        _stakers[_msgSender()].totalStakedAmount = _stakers[_msgSender()]
            .totalStakedAmount
            .add(newAmount);

        // Update Staker Block Stacked Info
        uint256 lastStakerBlockNumber =
            _getLastUserStakedBlockNumber(_msgSender());
        if (lastStakerBlockNumber == currentBlockNum) {
            // If Current Block Number is Last Staked Block Number, Update It
            _updateLastUserStakedBlockInfo(
                _msgSender(),
                _stakers[_msgSender()].totalStakedAmount
            );
        } else {
            // If New, Add New Block Staked Info
            _stakerInfoList[_msgSender()].push(
                BlockStakedInfo(
                    currentBlockNum,
                    _stakers[_msgSender()].totalStakedAmount
                )
            );
        }
    }

    /**
     * @dev Stake ETH to get YZY-ETH LP tokens
     */
    function _stake(uint256 amount_, uint256 lockTime) internal {
        // Check Initial Balance
        uint256 initialBalance =
            IERC20(_uniswapV2Pair).balanceOf(address(this));

        // Call swap for YZY&ETH
        require(
            swapAndLiquifyForYZY(amount_),
            "It is failed to swap between YZY and ETH and get LP tokens."
        );
        uint256 newBalance =
            IERC20(_uniswapV2Pair).balanceOf(address(this)).sub(initialBalance);

        require(newBalance > 0, "YZY Staking amount must be more than zero");

        // Update Stake Infos
        _updateStakeInfo(newBalance, lockTime);

        emit Staked(_msgSender(), newBalance);
    }

    /**
     * @dev Stake LP Token to get YZY-ETH LP tokens
     */
    function stakeLPToken(uint256 amount_, uint256 lockTime) external {
        require(!_isContract(_msgSender()), "Could not be a contract");
        require(amount_ > 0, "LP Staking amount must be more than zero.");
        require(
            lockTime <= _maxLockPeriod && lockTime >= _minLockPeriod,
            "Invalid lock time"
        );

        // Update Stake Infos
        _updateStakeInfo(amount_, lockTime);

        emit LPStaked(_msgSender(), amount_);
    }

    /**
     * @dev Unstake staked YZY-ETH LP tokens
     */
    function unstake() external onlyUnlocked {
        require(!_isContract(_msgSender()), "Could not be a contract");
        uint256 amount = _stakers[_msgSender()].totalStakedAmount;

        require(amount > 0, "No running stake");
        require(
            _totalStakedAmount >= amount,
            "User can't unstake more than total staked amount."
        );

        // Check Staker's Treasurey Reward
        uint256 treasuryAvailableReward =
            getTreasuryAvailableReward(_msgSender());
        if (treasuryAvailableReward > 0) {
            _withdrawTreasuryReward(treasuryAvailableReward);
        }

        // Check Staker's Quarterly Reward
        uint256 quarterlyAvailableReward =
            getQuarterlyAvailableReward(_msgSender());
        if (quarterlyAvailableReward > 0) {
            _withdrawQuarterlyReward(quarterlyAvailableReward);
        }

        // Decrease The Total Staked Amount
        _totalStakedAmount = _totalStakedAmount.sub(amount);
        // Update Total Staked Amount Info
        _updateLastTotalStakedBlockInfo(_totalStakedAmount);

        // Update Staker's Infos
        _stakers[_msgSender()].totalStakedAmount = 0;
        _stakers[_msgSender()].lastUnStakedBlockNum = block.number;
        // Pop All Staker's Block Infos
        uint256 stakerBlockInfoLength = _stakerInfoList[_msgSender()].length;
        for (uint256 i = 0; i < stakerBlockInfoLength; i++) {
            _stakerInfoList[_msgSender()].pop();
        }

        // Transfer LP tokens from contract to staker
        require(
            IUniswapV2Pair(_uniswapV2Pair).transfer(_msgSender(), amount),
            "It has failed to transfer LP tokens from contract to staker."
        );

        emit Unstaked(_msgSender(), amount);
    }

    /**
     * @dev To Get Total Staked Amount With Block Number
     */
    function _getTotalStakedAmountWithBlockNumber(uint256 currentBlockNum)
        internal
        view
        returns (uint256)
    {
        uint256 totalStakedAmount = 0;
        uint256 totalStakedLength = _totalStakedList.length;
        uint256 j = 0;

        if (totalStakedLength < 2) {
            return 0;
        }

        while (j < totalStakedLength - 1) {
            if (
                _totalStakedList[j].blockNum >= currentBlockNum &&
                _totalStakedList[j + 1].blockNum < currentBlockNum
            ) {
                totalStakedAmount = _totalStakedList[j].stakedAmount;
                break;
            }

            j = j.add(1);
        }

        if (totalStakedAmount == 0 && j == totalStakedLength - 1) {
            totalStakedAmount = _totalStakedAmount;
        }

        return totalStakedAmount;
    }

    /**
     * @dev API To Get Total Staked Amount With Block Number
     */
    function getTotalStakedAmountWithBlockNumber(uint256 currentBlockNum)
        external
        view
        returns (uint256)
    {
        return _getTotalStakedAmountWithBlockNumber(currentBlockNum);
    }

    /**
     * @dev To Get User Total Staked Amount With Block Number
     */
    function _getUserStakedAmountWithBlockNumber(
        address stakedAddress,
        uint256 currentBlockNum
    ) internal view returns (uint256) {
        uint256 userStakedAmount = 0;
        uint256 userStakedLength = _stakerInfoList[stakedAddress].length;
        uint256 j = 0;

        if (userStakedLength < 2) {
            return 0;
        }

        while (j < userStakedLength - 1) {
            if (
                _stakerInfoList[stakedAddress][j].blockNum >= currentBlockNum &&
                _stakerInfoList[stakedAddress][j + 1].blockNum < currentBlockNum
            ) {
                userStakedAmount = _stakerInfoList[stakedAddress][j]
                    .stakedAmount;
                break;
            }

            j = j.add(1);
        }

        if (userStakedAmount == 0 && j == userStakedLength - 1) {
            userStakedAmount = _stakers[stakedAddress].totalStakedAmount;
        }

        return userStakedAmount;
    }

    /**
     * @dev To Get User Total Staked Amount With Block Number
     */
    function getUserStakedAmountWithBlockNumber(
        address stakedAddress,
        uint256 currentBlockNum
    ) external view returns (uint256) {
        return
            _getUserStakedAmountWithBlockNumber(stakedAddress, currentBlockNum);
    }

    /**
     * @dev API To Get Staker's Treasury Available Reward
     */
    function getTreasuryAvailableReward(address account_)
        public
        view
        returns (uint256)
    {
        require(!_isContract(account_), "Could not be a contract");
        uint256 currentBlockNum = block.number;

        uint256 stakerInfoLength = _stakerInfoList[account_].length;
        uint256 availableTreasuryReward = 0;
        uint256 lastAvailableTreasuryRewardBlockNum =
            _getLastEraTime(
                _initialBlockNum,
                currentBlockNum,
                _treasuryFirstRewardBlockCount
            );

        // If User Never Stakes
        if (stakerInfoLength <= 1) {
            return availableTreasuryReward;
        }

        // For All Available Reward Blocks
        for (
            uint256 i = _stakers[account_].lastTreasuryRewardBlockNum;
            i < lastAvailableTreasuryRewardBlockNum;
            i++
        ) {
            // Check Current Block Has Available Reward
            uint256 blockTreasuryReward = _blockTreasuryRewards[i];
            if (blockTreasuryReward == 0) {
                blockTreasuryReward = _getInitialTreasuryBlockReward(i);
            }
            // Get Total Staked Amount With Blocknumber
            uint256 _totalStakedAmountWithBlockNumber =
                _getTotalStakedAmountWithBlockNumber(i);
            // Get User Staked Amount with Blocknumber
            uint256 _userStakedAmountWithBlockNumber =
                _getUserStakedAmountWithBlockNumber(account_, i);

            if (_totalStakedAmountWithBlockNumber > 0) {
                availableTreasuryReward = blockTreasuryReward
                    .mul(_userStakedAmountWithBlockNumber)
                    .div(_totalStakedAmountWithBlockNumber)
                    .add(availableTreasuryReward);
            }
        }

        return availableTreasuryReward;
    }

    /**
     * @dev API To Get Staker's Treasury Pending Reward
     */
    function getTreasuryPendingReward(address account_)
        public
        view
        returns (uint256)
    {
        require(!_isContract(account_), "Could not be a contract");
        uint256 currentBlockNum = block.number;

        uint256 stakerInfoLength = _stakerInfoList[account_].length;
        uint256 pendingTreasuryReward = 0;
        uint256 lastPendingTreasuryRewardBlockNum =
            _getLastEraTime(
                _initialBlockNum,
                currentBlockNum,
                _treasuryFirstRewardBlockCount
            );

        // If User Never Stakes
        if (stakerInfoLength <= 1) {
            return pendingTreasuryReward;
        }

        if (
            lastPendingTreasuryRewardBlockNum <
            _stakers[account_].lastTreasuryRewardBlockNum
        ) {
            lastPendingTreasuryRewardBlockNum = _stakers[account_]
                .lastTreasuryRewardBlockNum;
        }

        // For All Pending Reward Blocks
        for (
            uint256 i = lastPendingTreasuryRewardBlockNum;
            i < currentBlockNum;
            i++
        ) {
            // Check Current Block Has Pending Reward
            uint256 blockTreasuryReward = _blockTreasuryRewards[i];
            if (blockTreasuryReward == 0) {
                blockTreasuryReward = _getInitialTreasuryBlockReward(i);
            }
            // Get Total Staked Amount With Blocknumber
            uint256 _totalStakedAmountWithBlockNumber =
                _getTotalStakedAmountWithBlockNumber(i);
            // Get User Staked Amount with Blocknumber
            uint256 _userStakedAmountWithBlockNumber =
                _getUserStakedAmountWithBlockNumber(account_, i);

            if (_totalStakedAmountWithBlockNumber > 0) {
                pendingTreasuryReward = blockTreasuryReward
                    .mul(_userStakedAmountWithBlockNumber)
                    .div(_totalStakedAmountWithBlockNumber)
                    .add(pendingTreasuryReward);
            }
        }

        return pendingTreasuryReward;
    }

    /**
     * @dev API To Get Staker's Quarterly Available Reward
     */
    function getQuarterlyAvailableReward(address account_)
        public
        view
        returns (uint256)
    {
        require(!_isContract(account_), "Could not be a contract");
        uint256 currentBlockNum = block.number;

        uint256 stakerInfoLength = _stakerInfoList[account_].length;
        uint256 availableQuarterlyReward = 0;
        uint256 lastAvailableQuarterlyRewardBlockNum =
            _getLastEraTime(
                _initialBlockNum,
                currentBlockNum,
                _quarterlyFirstRewardBlockCount
            );

        // If User Never Stakes
        if (stakerInfoLength <= 1) {
            return availableQuarterlyReward;
        }

        // For All Available Reward Blocks
        for (
            uint256 i = _stakers[account_].lastQuarterlyRewardBlockNum;
            i < lastAvailableQuarterlyRewardBlockNum;
            i++
        ) {
            // Check Current Block Has Available Reward
            uint256 blockQuarterlyReward = _blockQuarterlyRewards[i];
            if (blockQuarterlyReward == 0) {
                blockQuarterlyReward = _getInitialQuarterlyBlockReward(i);
            }
            // Get Total Staked Amount With Blocknumber
            uint256 _totalStakedAmountWithBlockNumber =
                _getTotalStakedAmountWithBlockNumber(i);
            // Get User Staked Amount with Blocknumber
            uint256 _userStakedAmountWithBlockNumber =
                _getUserStakedAmountWithBlockNumber(account_, i);

            if (_totalStakedAmountWithBlockNumber > 0) {
                availableQuarterlyReward = blockQuarterlyReward
                    .mul(_userStakedAmountWithBlockNumber)
                    .div(_totalStakedAmountWithBlockNumber)
                    .add(availableQuarterlyReward);
            }
        }

        return availableQuarterlyReward;
    }

    /**
     * @dev API To Get Staker's Quarterly Pending Reward
     */
    function getQuarterlyPendingReward(address account_)
        public
        view
        returns (uint256)
    {
        require(!_isContract(account_), "Could not be a contract");
        uint256 currentBlockNum = block.number;

        uint256 stakerInfoLength = _stakerInfoList[account_].length;
        uint256 pendingQuarterlyReward = 0;
        uint256 lastPendingQuarterlyRewardBlockNum =
            _getLastEraTime(
                _initialBlockNum,
                currentBlockNum,
                _quarterlyFirstRewardBlockCount
            );

        // If User Never Stakes
        if (stakerInfoLength <= 1) {
            return pendingQuarterlyReward;
        }

        if (
            lastPendingQuarterlyRewardBlockNum <
            _stakers[account_].lastQuarterlyRewardBlockNum
        ) {
            lastPendingQuarterlyRewardBlockNum = _stakers[account_]
                .lastQuarterlyRewardBlockNum;
        }

        // For All Pending Reward Blocks
        for (
            uint256 i = lastPendingQuarterlyRewardBlockNum;
            i < currentBlockNum;
            i++
        ) {
            // Check Current Block Has Available Reward
            uint256 blockQuarterlyReward = _blockQuarterlyRewards[i];
            if (blockQuarterlyReward == 0) {
                blockQuarterlyReward = _getInitialQuarterlyBlockReward(i);
            }
            // Get Total Staked Amount With Blocknumber
            uint256 _totalStakedAmountWithBlockNumber =
                _getTotalStakedAmountWithBlockNumber(i);
            // Get User Staked Amount with Blocknumber
            uint256 _userStakedAmountWithBlockNumber =
                _getUserStakedAmountWithBlockNumber(account_, i);

            if (_totalStakedAmountWithBlockNumber > 0) {
                pendingQuarterlyReward = blockQuarterlyReward
                    .mul(_userStakedAmountWithBlockNumber)
                    .div(_totalStakedAmountWithBlockNumber)
                    .add(pendingQuarterlyReward);
            }
        }

        return pendingQuarterlyReward;
    }

    /**
     * @dev API to withdraw treasury available rewards to staker's wallet
     */
    function withdrawTreasuryAvailableReward() external returns (bool) {
        // Get Treasury Available Reward
        uint256 treasuryAvailableReward =
            getTreasuryAvailableReward(_msgSender());

        // Withdraw Treasury Available Reward
        _withdrawTreasuryReward(treasuryAvailableReward);

        // Update Staker's Last Treasury Reward BlockNumber
        _stakers[_msgSender()].lastTreasuryRewardBlockNum = _getLastEraTime(
            _initialBlockNum,
            block.number,
            _treasuryFirstRewardBlockCount
        );

        return true;
    }

    /**
     * @dev API to withdraw quarterly available rewards to staker's wallet
     */
    function withdrawQuarterlyAvailableReward() external returns (bool) {
        // Get Quarterly Available Reward
        uint256 quarterlyAvailableReward =
            getQuarterlyAvailableReward(_msgSender());

        // Withdraw Quarterly Available Reward
        _withdrawQuarterlyReward(quarterlyAvailableReward);

        // Update Staker's Last Quarterly Reward BlockNumber
        _stakers[_msgSender()].lastQuarterlyRewardBlockNum = _getLastEraTime(
            _initialBlockNum,
            block.number,
            _quarterlyFirstRewardBlockCount
        );

        return true;
    }

    /**
     * @dev API to withdraw treasury total(available + pending) rewards to staker's wallet
     * At that time, will burn 20% of treasury pending reward
     */
    function withdrawTreasuryTotalReward() external returns (bool) {
        // Get Treasury Available Reward
        uint256 treasuryAvailableReward =
            getTreasuryAvailableReward(_msgSender());

        // Get Treasury Pending Reward
        uint256 treasuryPendingReward = getTreasuryPendingReward(_msgSender());

        if (treasuryPendingReward > 0) {
            // Burn 20% of Treasury Pending Reward
            uint256 burnAmount = treasuryPendingReward.mul(_burnFee).div(10000);
            require(
                treasuryPendingReward > burnAmount,
                "Burn amount could not be more than pending reward."
            );
            require(
                IYZY(_yzyAddress).burnFromVault(burnAmount),
                "It's failed to burn yzy tokens."
            );
            treasuryPendingReward = treasuryPendingReward.sub(burnAmount);
        }

        // Get Treasury Total Reward
        uint256 treasuryTotalReward =
            treasuryAvailableReward.add(treasuryPendingReward);

        // Withdraw Treasury Total Reward
        _withdrawTreasuryReward(treasuryTotalReward);

        // Update Staker's Last Treasury Reward BlockNumber
        _stakers[_msgSender()].lastTreasuryRewardBlockNum = block.number;
        return true;
    }

    /**
     * @dev API to withdraw quarterly total(available +pending) rewards to staker's wallet
     * At that time, will burn 20% of quarterly pending reward
     */
    function withdrawQuarterlyTotalReward() external returns (bool) {
        // Get Quarterly Available Reward
        uint256 quarterlyAvailableReward =
            getQuarterlyAvailableReward(_msgSender());

        // Get Quarterly Pending Reward
        uint256 quarterlyPendingReward =
            getQuarterlyPendingReward(_msgSender());

        if (quarterlyPendingReward > 0) {
            // Burn 20% of Quarterly Pending Reward
            uint256 burnAmount =
                quarterlyPendingReward.mul(_burnFee).div(10000);
            require(
                quarterlyPendingReward > burnAmount,
                "Burn amount could not be more than pending reward."
            );
            require(
                IYZY(_yzyAddress).burnFromVault(burnAmount),
                "It's failed to burn yzy tokens."
            );
            quarterlyPendingReward = quarterlyPendingReward.sub(burnAmount);
        }

        // Get Quarterly Total Reward
        uint256 quarterlyTotalReward =
            quarterlyAvailableReward.add(quarterlyPendingReward);

        // Withdraw Quarterly Total Reward
        _withdrawQuarterlyReward(quarterlyTotalReward);

        // Update Staker's Last Quarterly Reward BlockNumber
        _stakers[_msgSender()].lastQuarterlyRewardBlockNum = block.number;

        return true;
    }

    /**
     * @dev API to get the total staked amount of all stakers
     */
    function totalStakedAmount() external view returns (uint256) {
        return _totalStakedAmount;
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
        emit EmergencyWithdrawToken(address(this), _msgSender(), tokenAmount);
    }

    /**
     * @dev Low level withdraw internal function
     */
    function _withdrawTreasuryReward(uint256 rewards) internal {
        require(rewards > 0, "No treasury reward state");

        uint256 treasureDevFee = uint256(_treasuryFee).add(uint256(_devFee));
        uint256 devFeeAmount =
            rewards.mul(uint256(_devFee)).div(10000).mul(treasureDevFee).div(
                10000
            );
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

        emit WithdrawTreasuryReward(_msgSender(), rewards);
    }

    /**
     * @dev Low level withdraw internal function
     */
    function _withdrawQuarterlyReward(uint256 rewards) internal {
        require(rewards > 0, "No reward state");

        uint256 wethOldBalance =
            IERC20(_wethTokenAddress).balanceOf(address(this));

        // Swap YZY -> WETH And Get Weth Tokens For Reward
        require(
            swapTokensForTokens(
                _yzyAddress,
                _wethTokenAddress,
                rewards,
                address(this)
            ),
            "It is failed to swap and transfer WETH token to User as reward."
        );

        // Get New Swaped ETH Amount
        uint256 wethNewBalance =
            IERC20(_wethTokenAddress).balanceOf(address(this)).sub(
                wethOldBalance
            );

        require(
            wethNewBalance > 0,
            "Weth reward amount must be more than zero"
        );

        uint256 yfiTokenReward =
            wethNewBalance.mul(_buyingYFITokenFee).div(10000);
        uint256 wbtcTokenReward =
            wethNewBalance.mul(_buyingWBTCTokenFee).div(10000);
        uint256 wethTokenReward =
            wethNewBalance.sub(yfiTokenReward).sub(wbtcTokenReward);

        // Transfer Weth Reward Tokens From Contract To Staker
        require(
            IERC20(_wethTokenAddress).transfer(_msgSender(), wethTokenReward),
            "It has failed to transfer weth tokens from contract to staker."
        );

        // Swap WETH -> YFI and give YFI token to User as reward
        require(
            swapTokensForTokens(
                _wethTokenAddress,
                _yfiTokenAddress,
                yfiTokenReward,
                _msgSender()
            ),
            "It is failed to swap and transfer YFI token to User as reward."
        );

        // Swap YZY -> WBTC and give WBTC token to User as reward
        require(
            swapTokensForTokens(
                _wethTokenAddress,
                _wbtcTokenAddress,
                wbtcTokenReward,
                _msgSender()
            ),
            "It is failed to swap and transfer WBTC token to User as reward."
        );

        emit WithdrawQuarterlyReward(_msgSender(), rewards);
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
