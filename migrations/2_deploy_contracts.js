const fs = require('fs');
const { ADDRESS } = require('../config');
const YZYToken = artifacts.require('YZYToken');
const Presale = artifacts.require('Presale');
const YZYVault = artifacts.require('YZYVault');
// only for test
const LPTestToken = artifacts.require('LPTestToken');

function expertContractJSON(contractName, instance) {
  const path = "./test/abis/" + contractName + ".json";
  const data = {
    contractName,
    "address": instance.address,
    "abi": instance.abi
  }

  fs.writeFile(path, JSON.stringify(data), (err) => {
    if (err) throw err;
    console.log('Contract data written to file');
  });  
};

module.exports = async function (deployer) {
  await deployer.deploy(Presale);
  await deployer.deploy(YZYToken, Presale.address, ADDRESS.AIRDROP_UNISWAP, ADDRESS.AIRDROP_MARKET, ADDRESS.AIRDROP_TEAM);
  await deployer.deploy(YZYVault);
  // only for test
  await deployer.deploy(LPTestToken, ADDRESS.AIRDROP_MARKET);

  expertContractJSON('Presale', Presale);
  expertContractJSON('YZYToken', YZYToken);
  expertContractJSON('YZYVault', YZYVault);
};
