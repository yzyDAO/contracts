const BigNumber = require('bignumber.js');
const { ADDRESS } = require('../config');
const YZYToken = require('./abis/YZYToken.json');
const YZYVault = require('./abis/YZYVault.json');
const Presale = require('./abis/Presale.json');

contract("YZYToken test", async accounts => {
  const IYZY = await new web3.eth.Contract(YZYToken.abi, YZYToken.address);
  const IYZYVault = await new web3.eth.Contract(YZYVault.abi, YZYVault.address);

  it("Should put 0 YZYToken in the first account", async () => {
    const balance = await IYZY.methods.balanceOf(accounts[0]).call();
    assert.equal(balance.valueOf(), 0);
  });

  it("Should be 5000E18 YZYToken in presale " + Presale.address, async () => {
    const balance = await IYZY.methods.balanceOf(Presale.address).call();
    assert.equal(balance.valueOf(), 5000E18);
  });

  it("Should be 4250E18 YZYToken in Uniswap " + ADDRESS.AIRDROP_UNISWAP, async () => {
    const balance = await IYZY.methods.balanceOf(ADDRESS.AIRDROP_UNISWAP).call();
    assert.equal(balance.valueOf(), 4250E18);
  });

  it("Should be 500E18 YZYToken in market " + ADDRESS.AIRDROP_MARKET, async () => {
    const balance = await IYZY.methods.balanceOf(ADDRESS.AIRDROP_MARKET).call();
    assert.equal(balance.valueOf(), 500E18);
  });

  it("Should be 250E18 YZYToken in team " + ADDRESS.AIRDROP_TEAM, async () => {
    const balance = await IYZY.methods.balanceOf(ADDRESS.AIRDROP_TEAM).call();
    assert.equal(balance.valueOf(), 250E18);
  });

  it("Should be token's name is 'Yzy Vault'", async () => {
    const name = await IYZY.methods.name().call();
    assert.equal(name, "Yzy Vault");
  });

  it("Should be token's symbol is 'YZY'", async () => {
    const symbol = await IYZY.methods.symbol().call();
    assert.equal(symbol, "YZY");
  });

  it("Should be decimal is 18", async () => {
    const decimal = await IYZY.methods.decimals().call();
    assert.equal(decimal.valueOf(), 18);
  });

  it("Should be total supply is 10000E18", async () => {
    const totalSupply = await IYZY.methods.totalSupply().call();
    assert.equal(totalSupply.valueOf(), 10000E18);
  });

  it("Should be trasfer fee is 100 in initial", async () => {
    const transferFee = await IYZY.methods.transferFee().call();
    assert.equal(transferFee, 100);
  });

  it("Should be changed transfer fee to 225" , async () => {
    await IYZY.methods.changeTransferFee('225').send({ from: accounts[0] });
    const transferFee = await IYZY.methods.transferFee().call();
    assert.equal(transferFee, 225);
  });

  it("Should be changed transfer fee to 100" , async () => {
    await IYZY.methods.changeTransferFee('100').send({ from: accounts[0] });
    const transferFee = await IYZY.methods.transferFee().call();
    assert.equal(transferFee, 100);
  });

  it("Should be Governance address is " + accounts[0], async () => {
    const governance = await IYZY.methods.governance().call();
    assert.equal(governance, accounts[0]);
  });
  
  it("Should be changed Governance address to " + accounts[1], async () => {
    await IYZY.methods.transferOwnership(accounts[1]).send({ from: accounts[0] });
    const governance = await IYZY.methods.governance().call();
    assert.equal(governance, accounts[1]);
  });

  it("Should be changed Governance address to " + accounts[0], async () => {
    await IYZY.methods.transferOwnership(accounts[0]).send({ from: accounts[1] });
    const governance = await IYZY.methods.governance().call();
    assert.equal(governance, accounts[0]);
  });

  it("Should be unpaused in initial", async () => {
    const paused = await IYZY.methods.paused().call();
    assert.equal(paused, false);
  });

  it("Should be paused", async () => {
    await IYZY.methods.pause().send({ from: accounts[0] });
    const paused = await IYZY.methods.paused().call();
    assert.equal(paused, true);
  });

  it("Should be unpaused", async () => {
    await IYZY.methods.unpause().send({ from: accounts[0] });
    const paused = await IYZY.methods.paused().call();
    assert.equal(paused, false);
  });

  it("Should be YZYVault address is zero in initial", async () => {
    const address = await IYZY.methods.YZYVault().call();
    assert.equal(address, 0);
  });

  it("Should be changed YZYVault address to " + YZYVault.address, async () => {
    await IYZY.methods.changeYZYVault(YZYVault.address).send({ from: accounts[0] });
    const address = await IYZY.methods.YZYVault().call();
    assert.equal(address, YZYVault.address);
  });

  it("Should be presale address is " + Presale.address, async () => {
    const address = await IYZY.methods.yzyPresale().call();
    assert.equal(address, Presale.address);
  });

  it("Should be changed presale address to " + accounts[1], async () => {
    await IYZY.methods.changeYzyPresale(accounts[1]).send({ from: accounts[0] });
    const address = await IYZY.methods.yzyPresale().call();
    assert.equal(address, accounts[1]);

    await IYZY.methods.changeYzyPresale(Presale.address).send({ from: accounts[0] });
    const changedAddress = await IYZY.methods.yzyPresale().call();
    assert.equal(changedAddress, Presale.address);

  });

  it("Should be sent token correctly", async () => {
    // change yzy address in YZYVault
    await IYZYVault.methods.changeYzyAddress(YZYToken.address).send({ from: accounts[0] });
    const YZYAddress = await IYZYVault.methods.yzyAddress().call();
    assert.equal(YZYAddress, YZYToken.address);

    const transferFee = new BigNumber(await IYZY.methods.transferFee().call());
    const sendAmount = new BigNumber(100E18);
    const feeAmount = sendAmount.times(transferFee).div(10000);

    // send 100 token from market to accounts[0]
    const expectedBalance = sendAmount.minus(feeAmount);
    let marketBalance = new BigNumber(await IYZY.methods.balanceOf(ADDRESS.AIRDROP_MARKET).call());
    const restBalance = marketBalance.minus(sendAmount);

    // await IYZY.methods.approve(accounts[0], sendAmount.toString(10)).send({ from: Presale.address });
    // await IYZY.methods.transferFrom(Presale.address, accounts[0], sendAmount.toString(10)).send({ from: Presale.address });
    await IYZY.methods.transfer(accounts[0], sendAmount.toString(10)).send({ from: ADDRESS.AIRDROP_MARKET });
    const receivedBalance = new BigNumber(await IYZY.methods.balanceOf(accounts[0]).call());
    const vaultBalance = new BigNumber(await IYZY.methods.balanceOf(YZYVault.address).call());
    marketBalance = new BigNumber(await IYZY.methods.balanceOf(ADDRESS.AIRDROP_MARKET).call());
    
    assert.equal(receivedBalance.toString(10), expectedBalance.toString(10));
    assert.equal(restBalance.toString(10), marketBalance.toString(10));
    assert.equal(feeAmount.toString(10), vaultBalance.toString(10));
  });
});