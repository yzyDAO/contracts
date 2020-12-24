const BigNumber = require('bignumber.js');
const { ADDRESS } = require('../config');
const YZYToken = artifacts.require('YZYToken');
const Presale = artifacts.require('Presale');
const YZYVault = artifacts.require('YZYVault');
const LPTestToken = artifacts.require('LPTestToken');

function toBN(value) {
  return new BigNumber(value);
}

function toBNString(value) {
  const bn = new BigNumber(value);
  return bn.toString(10);
}

contract("YZYVault test", async accounts => {
  it("Should be reward period is 1 days in initial", async () => {
    const IYZYVault = await YZYVault.deployed();
    const rewardPeriod = await IYZYVault.rewardPeriod.call();
    assert.equal(rewardPeriod.valueOf(), 86400);
  });

  it("Should be changed reward period is 2 days", async () => {
    const IYZYVault = await YZYVault.deployed();
    await IYZYVault.changeRewardPeriod(2*86400, { from: accounts[0] });
    let rewardPeriod = await IYZYVault.rewardPeriod.call();
    assert.equal(rewardPeriod.valueOf(), 86400*2);

    await IYZYVault.changeRewardPeriod(86400, { from: accounts[0] });
    rewardPeriod = await IYZYVault.rewardPeriod.call();
    assert.equal(rewardPeriod.valueOf(), 86400);
  });

  it("Should be Uniswap V2 address is zero in initial", async () => {
    const IYZYVault = await YZYVault.deployed();
    const address = await IYZYVault.uniswapV2Pair.call();
    assert.equal(address, 0);
  });

  it("Should be changed Uniswap V2 address to " + accounts[1], async () => {
    const IYZYVault = await YZYVault.deployed();
    await IYZYVault.changeUniswapV2Pair(accounts[1], { from: accounts[0] });
    const address = await IYZYVault.uniswapV2Pair.call();
    assert.equal(address, accounts[1]);
  });

  it("Should be changed YZY address to " + accounts[1], async () => {
    const IYZYVault = await YZYVault.deployed();
    await IYZYVault.changeYzyAddress(accounts[1], { from: accounts[0] });
    const address = await IYZYVault.yzyAddress.call();
    assert.equal(address, accounts[1]);
  });

  it("Should be dev fee receiver address is zero in initial", async () => {
    const IYZYVault = await YZYVault.deployed();
    const address = await IYZYVault.devFeeReciever.call();
    assert.equal(address, 0);
  });

  it("Should be changed dev fee receiver address to " + accounts[1], async () => {
    const IYZYVault = await YZYVault.deployed();
    await IYZYVault.changeDevFeeReciever(accounts[1], { from: accounts[0] });
    const address = await IYZYVault.yzyAddress.call();
    assert.equal(address, accounts[1]);
  });

  it("Should be dev fee is 400 in initial", async () => {
    const IYZYVault = await YZYVault.deployed();
    const devFee = await IYZYVault.devFee.call();
    assert.equal(devFee.valueOf(), 400);
  });

  it("Should be changed dev fee to 500", async () => {
    const IYZYVault = await YZYVault.deployed();
    await IYZYVault.changeDevFee(500, { from: accounts[0] });
    let devFee = await IYZYVault.devFee.call();
    assert.equal(devFee.valueOf(), 500);

    await IYZYVault.changeDevFee(400, { from: accounts[0] });
    devFee = await IYZYVault.devFee.call();
    assert.equal(devFee.valueOf(), 400);
  });

  // accounts[0] is deployer, governance
  it("Should be work perfectly for Vault", async () => {
    const IPresale = await Presale.deployed();
    const IYZY = await YZYToken.deployed();
    const IYZYVault = await YZYVault.deployed();
    const ILPTestToken = await LPTestToken.deployed();
    
    // check if airdrop done to correct addresses
    let uniswapBalance = toBNString(await IYZY.balanceOf.call(ADDRESS.AIRDROP_UNISWAP));
    assert.equal(uniswapBalance, toBNString(4250E18));

    let marketBalance = toBN(await IYZY.balanceOf.call(ADDRESS.AIRDROP_MARKET));

    let teamBalance = toBNString(await IYZY.balanceOf.call(ADDRESS.AIRDROP_TEAM));
    assert.equal(teamBalance, toBNString(250E18));

    // change yzy address in YZYVault
    await IYZYVault.changeYzyAddress(IYZY.address, { from: accounts[0] });
    const YZYAddress = await IYZYVault.yzyAddress.call();
    assert.equal(YZYAddress, IYZY.address);

    // change rewardPeriod to 5 min for test
    await IYZYVault.changeRewardPeriod(300, { from: accounts[0] });
    const rewardPeriod = await IYZYVault.rewardPeriod.call();
    assert.equal(rewardPeriod.valueOf(), 300);

    // change YZYVault address of YZYToken contract.
    await IYZY.changeYZYVault(IYZYVault.address, { from: accounts[0] });
    const YZYVaultAddress = await IYZY.YZYVault.call();
    assert.equal(YZYVaultAddress, IYZYVault.address);

    const transferFee = toBN(await IYZY.transferFee.call());
    let sendAmount = toBN(100E18);
    let feeAmount = sendAmount.times(transferFee).div(10000);

    // send 100 token from market address to accounts[0]
    let expectedReceivedAmount = sendAmount.minus(feeAmount);
    let restMarketBalance = marketBalance.minus(sendAmount);

    // transfer token
    await IYZY.transfer(accounts[1], sendAmount.toString(10), { from: ADDRESS.AIRDROP_MARKET });
    let receivedBalance = toBNString(await IYZY.balanceOf.call(accounts[1]));
    marketBalance = toBNString(await IYZY.balanceOf.call(ADDRESS.AIRDROP_MARKET));
    assert.equal(receivedBalance, expectedReceivedAmount.toString(10));
    assert.equal(marketBalance, restMarketBalance.toString(10));

    let rewardBalance = toBNString(await IYZY.balanceOf.call(YZYVault.address));
    assert.equal(rewardBalance, feeAmount.toString(10));

    // get contract startedTime
    const startedTime = toBNString(await IYZYVault.contractStartTime.call());
    const lastRewardedTime = toBNString(await IYZYVault.lastRewardedTime.call());
    assert.equal(startedTime, lastRewardedTime);

    // check epoch reward
    let epochReward = toBNString(await IYZYVault.epochReward.call(startedTime));
    assert.equal(epochReward, feeAmount.toString(10));

    let totalStakedAmount = toBNString(await IYZYVault.totalStakedAmount.call());
    assert.equal(totalStakedAmount, 0);

    let epochTotalStakedAmount = toBNString(await IYZYVault.epochTotalStakedAmount.call(startedTime));
    assert.equal(epochTotalStakedAmount, 0);

    let userTotalStakedAmount = toBNString(await IYZYVault.userTotalStakedAmount.call(accounts[0]));
    assert.equal(userTotalStakedAmount, 0);

    let userEpochStakedAmount = toBNString(await IYZYVault.userEpochStakedAmount.call(startedTime, accounts[0]));
    assert.equal(userEpochStakedAmount, 0);

    // get devFee
    const devFee = toBNString(await IYZYVault.devFee.call());

    // get rewards
    let reward = toBNString(await IYZYVault.getReward.call(ADDRESS.AIRDROP_MARKET));
    assert.equal(reward, 0);

    // try to stake sample erc20 token

    // check test token
    const testTokenTotalSupply = toBNString(await ILPTestToken.totalSupply.call());
    assert.equal(testTokenTotalSupply, toBNString(1000E18));

    let LPTokneBalance = toBNString(await ILPTestToken.balanceOf.call(ADDRESS.AIRDROP_MARKET));
    assert.equal(LPTokneBalance.toString(10), toBNString(1000E18));

    // set uniswap v2 pair contract address
    await IYZYVault.changeUniswapV2Pair(ILPTestToken.address, { from: accounts[0] });
    const uniswapV2PariAddress = await IYZYVault.uniswapV2Pair.call();
    assert.equal(uniswapV2PariAddress, ILPTestToken.address);

    // stake token
    // staker is ADDRESS.AIRDROP_MARKET
    await ILPTestToken.approve(IYZYVault.address, LPTokneBalance, { from: ADDRESS.AIRDROP_MARKET });
    await IYZYVault.stake(LPTokneBalance, { from: ADDRESS.AIRDROP_MARKET });

    const userStartedTime = toBNString(await IYZYVault.userStartedTime.call(ADDRESS.AIRDROP_MARKET));
    assert.equal(userStartedTime, lastRewardedTime);

    totalStakedAmount = toBNString(await IYZYVault.totalStakedAmount.call({ from: ADDRESS.AIRDROP_MARKET }));
    assert.equal(totalStakedAmount, LPTokneBalance);

    epochTotalStakedAmount = toBNString(await IYZYVault.epochTotalStakedAmount.call(startedTime, { from: ADDRESS.AIRDROP_MARKET }));
    assert.equal(epochTotalStakedAmount, LPTokneBalance);

    userTotalStakedAmount = toBNString(await IYZYVault.userTotalStakedAmount.call(ADDRESS.AIRDROP_MARKET));
    assert.equal(userTotalStakedAmount, LPTokneBalance);

    userEpochStakedAmount = toBNString(await IYZYVault.userEpochStakedAmount.call(startedTime, ADDRESS.AIRDROP_MARKET));
    assert.equal(userEpochStakedAmount, LPTokneBalance);

    // get rewards
    // rewards should be zero because of not passed reward period yet
    reward = toBNString(await IYZYVault.getReward.call(ADDRESS.AIRDROP_MARKET));
    assert.equal(reward, 0);

 
  });
});