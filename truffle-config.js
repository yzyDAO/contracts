// require('dotenv').config();

// var HDWalletProvider = require("truffle-hdwallet-provider");

module.exports = {
  networks: {
    development: {
      host: '127.0.0.1',
      port: 8545,
      network_id: '*', // Match any network id
      gas: 3500000,
      gasPrice: 20000000000,  // 20 gwei (in wei) (default: 100 gwei)
    },
    // mainnet: {
    //   provider: new HDWalletProvider(process.env.MNEMONIC, process.env.INFURA_NETWORK),
    //   network_id: '*',
    //   gas: 4000000,
    //   gasPrice: 20000000000,
    //   timeoutBlocks: 200,
    //   skipDryRun: true
    // }
  },
  mocha: {
    timeout: 500000
  },
  compilers: {
    solc: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      version: '^0.7.0'
    }
  }
};
