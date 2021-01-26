// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMath.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./IYZY.sol";
import "./IERC20.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";

contract YZYVault is Context, Ownable {
    using SafeMath for uint256;

    // States
    address public _uniswapV2Pair;
    address public _usdcETHV2Pair;
    address public _yzyAddress;
    address public _yfiTokenAddress;
    address public _wbtcTokenAddress;
    address public _wethTokenAddress;

    uint16 public _treasuryFee;
    uint16 public _lotteryFee;
    uint16 public _quarterlyFee;
    uint16 public _buyingYFITokenFee;
    uint16 public _buyingWBTCTokenFee;
    uint16 public _buyingWETHTokenFee;
    uint16 public _burnFee;

    IUniswapV2Router02 private _uniswapV2Router;

    // Period of reward distribution to stakers
    // It is `1 days` by default and could be changed
    // later only by Governance
    uint256 public _treasuryRewardPeriod;
    uint256 public _quarterlyRewardPeriod;
    uint256 public _maxLockPeriod;
    uint256 public _minLockPeriod;
    uint256 public _minDepositETHAmount;
    bool public _enabledLock;

    // save the timestamp for every period's reward
    uint256 public _contractStartTime;
    uint256 public _totalStakedAmount;
    address[] public _stakerList;

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
    uint256 private _lastTreasuryReward;
    uint256 private _lastQuarterlyReward;
    uint256 private _lotteryAmount;
    uint256 public _lotteryLimit;

    struct StakerInfo {
        uint256 stakedAmount;
        uint256 lastTreasuryRewardBlockNum;
        uint256 lastQuarterlyRewardBlockNum;
        uint256 lastUnStakedBlockNum;
        uint256 lockedTo;
    }

    struct BlockStakedInfo {
        uint256 blockNum;
        uint256 totalStakedAmount;
        uint256 userStakedAmount;
    }

    mapping(address => BlockStakedInfo[]) public _stakerInfoList;
    mapping(address => StakerInfo) public _stakers;

    // Events
    event Staked(address indexed account, uint256 amount);
    event LPStaked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);
    event ChangedEnabledLock(address indexed governance);
    event DisabledLock(address indexed governance);
    event ChangedMaximumLockPeriod(address indexed governance, uint256 value);
    event ChangedMinimumLockPeriod(address indexed governance, uint256 value);
    event ChangedMinimumETHDepositAmount(address indexed governance, uint256 value);
    event ChangedTreasuryRewardPeriod(address indexed governance, uint256 value);
    event ChangeQuarterlyRewardPeriod(address indexed governance, uint256 value);
    event ChangedUniswapV2Pair(address indexed governance, address indexed uniswapV2Pair);
    event ChangedUniswapV2Router(address indexed governance, address indexed uniswapV2Pair);
    event ChangedYzyAddress(address indexed governance, address indexed yzyAddress);
    event ChangedYfiTokenAddress(address indexed governance, address indexed yfiAddress);
    event ChangedWbtcTokenAddress(address indexed governance, address indexed wbtcAddress);
    event ChangedWethTokenAddress(address indexed governance, address indexed wethAddress);
    event EmergencyWithdrawToken(address indexed from, address indexed to, uint256 amount);
    event WithdrawTreasuryReward(address indexed staker, uint256 amount);
    event WithdrawQuarterlyReward(address indexed staker, uint256 amount);
    event ChangedTreasuryFee(address indexed governance, uint16 value);
    event ChangedQuarterlyFee(address indexed governance, uint16 value);
    event ChangedBuyingYFITokenFee(address indexed governance, uint16 value);
    event ChangedBuyingWBTCTokenFee(address indexed governance, uint16 value);
    event ChangedBuyingWETHTokenFee(address indexed governance, uint16 value);
    event ChangedBurnFee(address indexed governance, uint16 value);
    event SwapAndLiquifyForYZY(address indexed msgSender, uint256 totAmount, uint256 ethAmount, uint256 yzyAmount);
    event ChangedLotteryFee(address indexed governance, uint16 value);
    event ChangeLotteryLimit(address indexed msgSender, uint256 lotteryLimit);
    event ChangedYUsdcETHV2PairAddress(address indexed msgSender, address usdcETHV2Pair);
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
            !_enabledLock ||
                (_stakers[_msgSender()].lockedTo > 0 &&
                    block.timestamp >= _stakers[_msgSender()].lockedTo),
            "Staking pool is locked"
        );
        _;
    }

    constructor() {
        _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        _treasuryRewardPeriod = 14 days;
        _quarterlyRewardPeriod = 90 days;
        _contractStartTime = block.timestamp;

        _treasuryFee = 7600; // 76% of taxFee to treasuryFee
        _lotteryFee = 400; // 4% of lottery Fee
        _quarterlyFee = 2000; // 20% of taxFee to buyingTokenFee
        _buyingYFITokenFee = 5000; // 50% of buyingTokenFee to buy YFI token
        _buyingWBTCTokenFee = 3000; // 30% of buyingTokenFee to buy WBTC token
        _buyingWETHTokenFee = 2000; // 20% of buyingTokenFee to buy WETH token
        _burnFee = 2000; // 20% of pending reward to burn when staker request to withdraw pending reward

        _minDepositETHAmount = 1E17;
        _maxLockPeriod = 365 days; // around 1 year
        _minLockPeriod = 90 days; // around 3 months
        _enabledLock = true;

        _lotteryLimit = 1200E18; // $1200

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
            .mul((uint256)(_treasuryFee).add(_lotteryFee))
            .div(10000)
            .div(_treasuryFirstRewardBlockCount);

        _initialFirstQuarterlyReward = (uint256)(2000E18)
            .sub(
            _initialFirstTreasuryReward.mul(_treasuryFirstRewardBlockCount)
        )
            .div(_quarterlyFirstRewardBlockCount);

        _initialYearlyTreasuryReward = (uint256)(7900E18)
            .mul((uint256)(_treasuryFee).add(_lotteryFee))
            .div(10000)
            .div(_yearlyRewardBlockCount);

        _initialYearlyQuarterlyReward = (uint256)(7900E18)
            .sub(_initialYearlyTreasuryReward.mul(_yearlyRewardBlockCount))
            .div(_yearlyRewardBlockCount);
    }

    function setupAddresses(
        address uniswapV2Pair_,
        address yzyAddress_,
        address yfiTokenAddress_,
        address wbtcTokenAddress_,
        address wethTokenAddress_,
        address usdtETHV2Pair_
    ) external onlyGovernance {
        _uniswapV2Pair = uniswapV2Pair_;
        _yzyAddress = yzyAddress_;
        _yfiTokenAddress = yfiTokenAddress_;
        _wbtcTokenAddress = wbtcTokenAddress_;
        _wethTokenAddress = wethTokenAddress_;
        _usdcETHV2Pair = usdtETHV2Pair_;
    }

    /**
     * @dev Change Minimum Deposit ETH Amount. Call by only Governance.
     */
    function changeMinimumDepositETHAmount(uint256 minDepositETHAmount_) external onlyGovernance {
        _minDepositETHAmount = minDepositETHAmount_;
        emit ChangedMinimumETHDepositAmount(governance(), minDepositETHAmount_);
    }

    /**
     * @dev Change YFI Token contract address. Call by only Governance.
     */
    function changeYfiTokenAddress(address yfiAddress_) external onlyGovernance {
        _yfiTokenAddress = yfiAddress_;
        emit ChangedYfiTokenAddress(governance(), yfiAddress_);
    }

    /**
     * @dev Change usdc-eth pair contract address. Call by only Governance.
     */
    function changeUsdcETHV2PairAddress(address address_) external onlyGovernance {
        _usdcETHV2Pair = address_;
        emit ChangedYUsdcETHV2PairAddress(governance(), address_);
    }

    /**
     * @dev Change WBTC Token address. Call by only Governance.
     */
    function changeWbtcTokenAddress(address wbtcAddress_) external onlyGovernance {
        _wbtcTokenAddress = wbtcAddress_;
        emit ChangedWbtcTokenAddress(governance(), wbtcAddress_);
    }

    /**
     * @dev Change WETH Token address. Call by only Governance.
     */
    function changeWethTokenAddress(address wethAddress_) external onlyGovernance {
        _wethTokenAddress = wethAddress_;
        emit ChangedWethTokenAddress(governance(), wethAddress_);
    }

    /**
     * @dev Change value of treasury reward period. Call by only Governance.
     */
    function changeTreasuryRewardPeriod(uint256 treasuryRewardPeriod_) external onlyGovernance {
        _treasuryRewardPeriod = treasuryRewardPeriod_;
        emit ChangedTreasuryRewardPeriod(governance(), treasuryRewardPeriod_);
    }

    /**
     * @dev Change value of quarterly reward period. Call by only Governance.
     */
    function changeQuarterlyRewardPeriod(uint256 quarterlyRewardPeriod_) external onlyGovernance {
        _quarterlyRewardPeriod = quarterlyRewardPeriod_;
        emit ChangeQuarterlyRewardPeriod(governance(), quarterlyRewardPeriod_);
    }

    /**
     * @dev Enable lock functionality. Call by only Governance.
     */
    function setLock(bool lock_) external onlyGovernance {
        _enabledLock = lock_;
        emit ChangedEnabledLock(governance());
    }

    /**
     * @dev Change maximun lock period. Call by only Governance.
     */
    function changedMaximumLockPeriod(uint256 maxLockPeriod_) external onlyGovernance {
        _maxLockPeriod = maxLockPeriod_;
        emit ChangedMaximumLockPeriod(governance(), _maxLockPeriod);
    }

    /**
     * @dev Change minimum lock period. Call by only Governance.
     */
    function changedMinimumLockPeriod(uint256 minLockPeriod_) external onlyGovernance {
        _minLockPeriod = minLockPeriod_;
        emit ChangedMinimumLockPeriod(governance(), _minLockPeriod);
    }

    /**
     * @dev Change YZY-ETH Uniswap V2 Pair address. Call by only Governance.
     */
    function changeUniswapV2Pair(address uniswapV2Pair_) external onlyGovernance {
        _uniswapV2Pair = uniswapV2Pair_;
        emit ChangedUniswapV2Pair(governance(), uniswapV2Pair_);
    }

    /**
     * @dev Change address of Uniswap V2Router. Call by only Governance.
     */
    function changeUniswapV2Router(address uniswapV2Router_) external onlyGovernance {
        _uniswapV2Router = IUniswapV2Router02(uniswapV2Router_);
        emit ChangedUniswapV2Router(governance(), address(uniswapV2Router_));
    }

    /**
     * @dev Change YZY Token contract address. Call by only Governance.
     */
    function changeYzyAddress(address yzyAddress_) external onlyGovernance {
        _yzyAddress = yzyAddress_;
        emit ChangedYzyAddress(governance(), yzyAddress_);
    }

    /**
     * @dev Update the treasury fee for this contract
     * defaults at 76.00% of taxFee, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeTreasuryFee(uint16 treasuryFee_) external onlyGovernance {
        _treasuryFee = treasuryFee_;
        emit ChangedTreasuryFee(governance(), treasuryFee_);
    }

    /**
     * @dev Update the burn fee for this contract
     * defaults at 20.00% of Pending Reward Amount, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBurnFee(uint16 burnFee_) external onlyGovernance {
        _burnFee = burnFee_;
        emit ChangedBurnFee(governance(), burnFee_);
    }

    /**
     * @dev Update the dev fee for this contract
     * defaults at 4.00% of taxFee, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeLotteryFee(uint16 lotteryFee_) external onlyGovernance {
        _lotteryFee = lotteryFee_;
        emit ChangedLotteryFee(governance(), lotteryFee_);
    }

    /**
     * @dev Update the Quarterly fee for this contract
     * defaults at 20.00% of taxFee, It can be set on only by YZY governance.
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeQuarterlyFee(uint16 quarterlyFee_) external onlyGovernance {
        _quarterlyFee = quarterlyFee_;
        emit ChangedQuarterlyFee(governance(), quarterlyFee_);
    }

    /**
     * @dev Update the buying YFI token fee for this contract
     * defaults at 50.00% of buyingTokenFee
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBuyingYFITokenFee(uint16 buyingYFITokenFee_) external onlyGovernance {
        _buyingYFITokenFee = buyingYFITokenFee_;
        emit ChangedBuyingYFITokenFee(governance(), buyingYFITokenFee_);
    }

    /**
     * @dev Update the buying WBTC token fee for this contract
     * defaults at 30.00% of buyingTokenFee
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBuyingWBTCTokenFee(uint16 buyingWBTCTokenFee_) external onlyGovernance {
        _buyingWBTCTokenFee = buyingWBTCTokenFee_;
        emit ChangedBuyingWBTCTokenFee(governance(), buyingWBTCTokenFee_);
    }

    /**
     * @dev Update the buying WETH token fee for this contract
     * defaults at 20.00% of buyingTokenFee
     * Note contract owner is meant to be a governance contract allowing YZY governance consensus
     */
    function changeBuyingWETHTokenFee(uint16 buyingWETHTokenFee_) external onlyGovernance {
        _buyingWETHTokenFee = buyingWETHTokenFee_;
        emit ChangedBuyingWETHTokenFee(governance(), buyingWETHTokenFee_);
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
     * @dev Get Treasury Period Reward
     */
    function _getTreasuryPeriodReward(
        uint256 startBlockNum,
        uint256 endBlockNum
    ) internal view returns (uint256) {
        if (startBlockNum > endBlockNum) {
            return 0;
        }

        uint256 treasuryPeriodReward = 0;

        // If Period is in First Reward Period
        if (endBlockNum < _treasuryFirstRewardEndedBlockNum) {
            treasuryPeriodReward = endBlockNum.sub(startBlockNum).mul(
                _initialFirstTreasuryReward
            );
        } else {
            if (
                startBlockNum < _treasuryFirstRewardEndedBlockNum &&
                endBlockNum < _yearlyRewardEndedBlockNum
            ) {
                treasuryPeriodReward = _treasuryFirstRewardEndedBlockNum
                    .sub(startBlockNum)
                    .mul(_initialFirstTreasuryReward);
                treasuryPeriodReward = endBlockNum
                    .sub(_treasuryFirstRewardEndedBlockNum)
                    .mul(_initialYearlyTreasuryReward)
                    .add(treasuryPeriodReward);
            }
            if (
                startBlockNum > _treasuryFirstRewardEndedBlockNum &&
                startBlockNum < _yearlyRewardEndedBlockNum
            ) {
                if (endBlockNum < _yearlyRewardEndedBlockNum) {
                    treasuryPeriodReward = endBlockNum.sub(startBlockNum).mul(
                        _initialYearlyTreasuryReward
                    );
                } else {
                    treasuryPeriodReward = _yearlyRewardEndedBlockNum
                        .sub(startBlockNum)
                        .mul(_initialYearlyTreasuryReward);
                }
            }
        }

        return treasuryPeriodReward;
    }

    /**
     * @dev Get Quarterly Period Reward
     */
    function _getQuarterlyPeriodReward(
        uint256 startBlockNum,
        uint256 endBlockNum
    ) internal view returns (uint256) {
        if (startBlockNum > endBlockNum) {
            return 0;
        }

        uint256 quarterlyPeriodReward = 0;

        // If Period is in First Reward Period
        if (endBlockNum < _quarterlyFirstRewardEndedBlockNum) {
            quarterlyPeriodReward = endBlockNum.sub(startBlockNum).mul(
                _initialFirstQuarterlyReward
            );
        } else {
            if (
                startBlockNum < _quarterlyFirstRewardEndedBlockNum &&
                endBlockNum < _yearlyRewardEndedBlockNum
            ) {
                quarterlyPeriodReward = _quarterlyFirstRewardEndedBlockNum
                    .sub(startBlockNum)
                    .mul(_initialFirstQuarterlyReward);
                quarterlyPeriodReward = endBlockNum
                    .sub(_quarterlyFirstRewardEndedBlockNum)
                    .mul(_initialYearlyQuarterlyReward)
                    .add(quarterlyPeriodReward);
            }
            if (
                startBlockNum > _quarterlyFirstRewardEndedBlockNum &&
                startBlockNum < _yearlyRewardEndedBlockNum
            ) {
                if (endBlockNum < _yearlyRewardEndedBlockNum) {
                    quarterlyPeriodReward = endBlockNum.sub(startBlockNum).mul(
                        _initialYearlyQuarterlyReward
                    );
                } else {
                    quarterlyPeriodReward = _yearlyRewardEndedBlockNum
                        .sub(startBlockNum)
                        .mul(_initialYearlyQuarterlyReward);
                }
            }
        }

        return quarterlyPeriodReward;
    }

    /**
     * @dev Add fee to era reward variable
     * Note Call by only YZY token contract
     */
    function addEraReward(uint256 amount_) external onlyYzy returns (bool) {
        uint256 treasuryLotteryFee = uint256(_treasuryFee).add(uint256(_lotteryFee));
        uint256 treasuryRewardAmount = amount_.mul(treasuryLotteryFee).div(10000);
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
        _lastTreasuryReward = _lastTreasuryReward.add(treasuryRewardAmount);

        // Update Quarterly Rewards
        _lastQuarterlyReward = _lastQuarterlyReward.add(quarterlyRewardAmount);

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

    function stake(uint256 lockTime) external payable returns (bool) {
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

        return _sendLotteryAmount();
    }

    /**
     * @dev Update Total Stake & User Stake Infos
     */
    function _updateStakeInfo(uint256 newAmount, uint256 lockTime) internal {
        uint256 currentBlockNum = block.number;

        // Update Staker's Locked Time
        if (_stakers[_msgSender()].lockedTo == 0) {
            _stakers[_msgSender()].lockedTo = lockTime.add(block.timestamp);
            _stakerList.push(_msgSender());
        }

        // Update Staker's Initial Info
        if (_stakers[_msgSender()].stakedAmount == 0) {
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
                    BlockStakedInfo(_initialBlockNum, 0, _totalStakedAmount)
                );
            } else {
                // If User Restakes
                // Initialize Staker's Block Staked Info
                _stakerInfoList[_msgSender()].push(
                    BlockStakedInfo(
                        _stakers[_msgSender()].lastUnStakedBlockNum,
                        0,
                        _totalStakedAmount
                    )
                );
            }
        }

        // Increase the total staked amount
        _totalStakedAmount = _totalStakedAmount.add(newAmount);

        // Increase staked amount of the staker
        _stakers[_msgSender()].stakedAmount = _stakers[_msgSender()]
            .stakedAmount
            .add(newAmount);

        // Update Staker Block Stacked Info
        _stakerInfoList[_msgSender()].push(
            BlockStakedInfo(
                currentBlockNum,
                _totalStakedAmount,
                _stakers[_msgSender()].stakedAmount
            )
        );

        // Update Last Block Number
        for (uint256 i = 0; i < _stakerList.length; i++) {
            uint256 length = _stakerInfoList[_stakerList[i]].length;
            if (length > 1) {
                _stakerInfoList[_stakerList[i]][length - 1]
                    .totalStakedAmount = _totalStakedAmount;
            }
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
    function stakeLPToken(uint256 amount_, uint256 lockTime) external returns (bool) {
        require(!_isContract(_msgSender()), "Could not be a contract");
        require(amount_ > 0, "LP Staking amount must be more than zero.");
        require(
            lockTime <= _maxLockPeriod && lockTime >= _minLockPeriod,
            "Invalid lock time"
        );

        // Update Stake Infos
        _updateStakeInfo(amount_, lockTime);

        emit LPStaked(_msgSender(), amount_);

        return _sendLotteryAmount();
    }

    /**
     * @dev Unstake staked YZY-ETH LP tokens
     */
    function unstake() external onlyUnlocked returns (bool) {
        require(!_isContract(_msgSender()), "Could not be a contract");
        uint256 amount = _stakers[_msgSender()].stakedAmount;

        require(amount > 0, "No running stake");
        require(
            _totalStakedAmount >= amount,
            "User can't unstake more than total staked amount."
        );

        // Withdraw Treasury TotalReward
        withdrawTreasuryTotalReward();

        // Withdraw Quarterly TotalReward
        withdrawQuarterlyTotalReward();

        // Decrease The Total Staked Amount
        _totalStakedAmount = _totalStakedAmount.sub(amount);

        // Update Staker's Infos
        _stakers[_msgSender()].stakedAmount = 0;
        _stakers[_msgSender()].lastUnStakedBlockNum = block.number;
        // Pop All Staker's Block Infos
        uint256 stakerBlockInfoLength = _stakerInfoList[_msgSender()].length;
        for (uint256 i = 0; i < stakerBlockInfoLength; i++) {
            _stakerInfoList[_msgSender()].pop();
        }

        // update staker list
        for (uint256 i = 0; i < _stakerList.length; i++) {
            if (_stakerList[i] == _msgSender()) {
                _stakerList[i] = _stakerList[_stakerList.length - 1];
                _stakerList.pop();
                break;
            }
        }

        // Transfer LP tokens from contract to staker
        require(
            IUniswapV2Pair(_uniswapV2Pair).transfer(_msgSender(), amount),
            "It has failed to transfer LP tokens from contract to staker."
        );

        emit Unstaked(_msgSender(), amount);

        return _sendLotteryAmount();
    }

    /**
     * @dev Get Treasury Reward
     */
    function _getTreasuryReward(
        address account_,
        uint256 from,
        uint256 to,
        uint256 length
    ) internal view returns (uint256) {
        uint256 treasuryReward = 0;

        if (from >= to) {
            return treasuryReward;
        }

        for (uint256 i = 1; i < length; i++) {
            if (_stakerInfoList[account_][i - 1].totalStakedAmount > 0) {
                if (
                    _stakerInfoList[account_][i - 1].blockNum <= from &&
                    _stakerInfoList[account_][i].blockNum > from
                ) {
                    uint256 toBlockNumber =
                        _stakerInfoList[account_][i].blockNum;
                    if (toBlockNumber > to) {
                        toBlockNumber = to;
                    }
                    treasuryReward = treasuryReward.add(
                        _getTreasuryPeriodReward(from, toBlockNumber)
                            .mul(
                            _stakerInfoList[account_][i - 1]
                                .userStakedAmount
                        )
                            .div(
                            _stakerInfoList[account_][i - 1].totalStakedAmount
                        )
                    );
                    continue;
                }
                if (
                    _stakerInfoList[account_][i - 1].blockNum > from &&
                    _stakerInfoList[account_][i].blockNum < to
                ) {
                    treasuryReward = treasuryReward.add(
                        _getTreasuryPeriodReward(
                            _stakerInfoList[account_][i - 1]
                                .blockNum,
                            _stakerInfoList[account_][i]
                                .blockNum
                        )
                            .mul(
                            _stakerInfoList[account_][i - 1]
                                .userStakedAmount
                        )
                            .div(
                            _stakerInfoList[account_][i - 1].totalStakedAmount
                        )
                    );
                    continue;
                }
                if (
                    _stakerInfoList[account_][i - 1].blockNum <= to &&
                    _stakerInfoList[account_][i].blockNum > to
                ) {
                    treasuryReward = treasuryReward.add(
                        _getTreasuryPeriodReward(
                            _stakerInfoList[account_][i - 1]
                                .blockNum,
                            to
                        )
                            .mul(
                            _stakerInfoList[account_][i - 1]
                                .userStakedAmount
                        )
                            .div(
                            _stakerInfoList[account_][i - 1].totalStakedAmount
                        )
                    );
                }
            }
        }

        if (
            _stakerInfoList[account_][length - 1].totalStakedAmount > 0 &&
            _stakerInfoList[account_][length - 1].blockNum <= to
        ) {
            uint256 startBlockNum =
                _stakerInfoList[account_][length - 1].blockNum;
            if (startBlockNum < from) {
                startBlockNum = from;
            }
            treasuryReward = treasuryReward.add(
                _getTreasuryPeriodReward(startBlockNum, to)
                    .mul(_stakerInfoList[account_][length - 1].userStakedAmount)
                    .div(
                    _stakerInfoList[account_][length - 1].totalStakedAmount
                )
            );
        }

        return treasuryReward;
    }

    /**
     * @dev Get Quarterly Reward
     */
    function _getQuarterlyReward(
        address account_,
        uint256 from,
        uint256 to,
        uint256 length
    ) internal view returns (uint256) {
        uint256 quarterlyReward = 0;

        if (from >= to) {
            return quarterlyReward;
        }

        for (uint256 i = 1; i < length; i++) {
            if (_stakerInfoList[account_][i - 1].totalStakedAmount > 0) {
                if (
                    _stakerInfoList[account_][i - 1].blockNum <= from &&
                    _stakerInfoList[account_][i].blockNum > from
                ) {
                    uint256 toBlockNumber =
                        _stakerInfoList[account_][i].blockNum;
                    if (toBlockNumber > to) {
                        toBlockNumber = to;
                    }
                    quarterlyReward = quarterlyReward.add(
                        _getQuarterlyPeriodReward(from, toBlockNumber)
                            .mul(
                            _stakerInfoList[account_][i - 1]
                                .userStakedAmount
                        )
                            .div(
                            _stakerInfoList[account_][i - 1].totalStakedAmount
                        )
                    );
                    continue;
                }
                if (
                    _stakerInfoList[account_][i - 1].blockNum > from &&
                    _stakerInfoList[account_][i].blockNum < to
                ) {
                    quarterlyReward = quarterlyReward.add(
                        _getQuarterlyPeriodReward(
                            _stakerInfoList[account_][i - 1]
                                .blockNum,
                            _stakerInfoList[account_][i]
                                .blockNum
                        )
                            .mul(
                            _stakerInfoList[account_][i - 1]
                                .userStakedAmount
                        )
                            .div(
                            _stakerInfoList[account_][i - 1].totalStakedAmount
                        )
                    );
                    continue;
                }
                if (
                    _stakerInfoList[account_][i - 1].blockNum <= to &&
                    _stakerInfoList[account_][i].blockNum > to
                ) {
                    quarterlyReward = quarterlyReward.add(
                        _getQuarterlyPeriodReward(
                            _stakerInfoList[account_][i - 1]
                                .blockNum,
                            to
                        )
                            .mul(
                            _stakerInfoList[account_][i - 1]
                                .userStakedAmount
                        )
                            .div(
                            _stakerInfoList[account_][i - 1].totalStakedAmount
                        )
                    );
                }
            }
        }

        if (
            _stakerInfoList[account_][length - 1].totalStakedAmount > 0 &&
            _stakerInfoList[account_][length - 1].blockNum <= to
        ) {
            uint256 startBlockNum =
                _stakerInfoList[account_][length - 1].blockNum;
            if (startBlockNum < from) {
                startBlockNum = from;
            }
            quarterlyReward = quarterlyReward.add(
                _getQuarterlyPeriodReward(startBlockNum, to)
                    .mul(_stakerInfoList[account_][length - 1].userStakedAmount)
                    .div(
                    _stakerInfoList[account_][length - 1].totalStakedAmount
                )
            );
        }

        return quarterlyReward;
    }

    /**
     * @dev API To Get Staker's Treasury Available Reward
     */
    function getTreasuryAvailableReward(address account_)
        public
        view
        returns (uint256)
    {
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

        availableTreasuryReward = _getTreasuryReward(
            account_,
            _stakers[account_].lastTreasuryRewardBlockNum,
            lastAvailableTreasuryRewardBlockNum,
            stakerInfoLength
        );
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

        pendingTreasuryReward = _getTreasuryReward(
            account_,
            lastPendingTreasuryRewardBlockNum,
            currentBlockNum,
            stakerInfoLength
        );

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

        availableQuarterlyReward = _getQuarterlyReward(
            account_,
            _stakers[account_].lastQuarterlyRewardBlockNum,
            lastAvailableQuarterlyRewardBlockNum,
            stakerInfoLength
        );

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

        pendingQuarterlyReward = _getQuarterlyReward(
            account_,
            lastPendingQuarterlyRewardBlockNum,
            currentBlockNum,
            stakerInfoLength
        );
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
    function withdrawTreasuryTotalReward() public returns (bool) {
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
    function withdrawQuarterlyTotalReward() public returns (bool) {
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
     * @dev API to get the staker's staked amount
     */
    function userTotalStakedAmount(address account_) external view returns (uint256) {
        return _stakers[account_].stakedAmount;
    }

    /**
     * @dev API to get the staker's rank
     */
    function userRank(address account_) external view returns (uint256) {
        require(account_ != address(0), "Invalid address");

        uint256 rank = 1;
        uint256 userStakedAmount = _stakers[account_].stakedAmount;

        for (uint256 i = 0; i < _stakerList.length; i++) {
            address staker = _stakerList[i];
            if (
                staker != account_ &&
                userStakedAmount < _stakers[staker].stakedAmount
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
     * @dev API to get lottery yzy amount
     */
    function getLotteryAmount() external view onlyGovernance returns (uint256) {
        return _lotteryAmount;
    }

    function changeLotteryLimit(uint256 lotteryLimit_) external onlyGovernance {
        _lotteryLimit = lotteryLimit_;
        emit ChangeLotteryLimit(_msgSender(), lotteryLimit_);
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

        uint256 treasureLotteryFee = uint256(_treasuryFee).add(uint256(_lotteryFee));
        uint256 lotteryFeeAmount =rewards.mul(uint256(_lotteryFee)).div(10000).mul(treasureLotteryFee).div(10000);
        _lotteryAmount = _lotteryAmount.add(lotteryFeeAmount);
        uint256 actualRewards = rewards.sub(lotteryFeeAmount);

        // Transfer reward tokens from contract to staker
        require(
            IYZY(_yzyAddress).transferWithoutFee(_msgSender(), actualRewards),
            "It has failed to transfer tokens from contract to staker."
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

        uint256 yfiTokenReward = wethNewBalance.mul(_buyingYFITokenFee).div(10000);
        uint256 wbtcTokenReward = wethNewBalance.mul(_buyingWBTCTokenFee).div(10000);
        uint256 wethTokenReward = wethNewBalance.sub(yfiTokenReward).sub(wbtcTokenReward);

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

    /**
     * @dev internal function to send lottery rewards
     */
    function _sendLotteryAmount() internal returns (bool) {
        (uint256 usdcAmount, uint256 ethAmount1, ) = IUniswapV2Pair(_usdcETHV2Pair).getReserves();
        (uint256 yzyAmount, uint256 ethAmount2, ) = IUniswapV2Pair(_uniswapV2Pair).getReserves();

        if (ethAmount1 <= 0 || yzyAmount <= 0)
            return false;

        uint256 yzyPrice = ethAmount2.mul(1 ether).div(ethAmount1).mul(usdcAmount).div(yzyAmount);
        uint256 lotteryValue = yzyPrice.mul(_lotteryAmount).div(1 ether);

        if (lotteryValue > 0 && lotteryValue >= _lotteryLimit) {
            uint256 amount = _lotteryLimit.div(yzyPrice);
            if (amount > _lotteryAmount)
                amount = _lotteryAmount;
            IYZY(_yzyAddress).transferWithoutFee(_msgSender(), amount);
            _lotteryAmount = _lotteryAmount.sub(amount);

            return true;
        }

        return false;
    }
}
