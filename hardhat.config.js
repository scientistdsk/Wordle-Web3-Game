require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },

  networks: {
    // Hedera Testnet
    testnet: {
      url: process.env.HEDERA_TESTNET_RPC_URL || "https://testnet.hashio.io/api",
      chainId: 296,
      accounts: process.env.HEDERA_TESTNET_OPERATOR_KEY ? [process.env.HEDERA_TESTNET_OPERATOR_KEY] : [],
      timeout: 60000,
      gas: "auto",
      gasPrice: "auto"
    },

    // Hedera Mainnet
    mainnet: {
      url: process.env.HEDERA_MAINNET_RPC_URL || "https://mainnet.hashio.io/api",
      chainId: 295,
      accounts: process.env.HEDERA_MAINNET_OPERATOR_KEY ? [process.env.HEDERA_MAINNET_OPERATOR_KEY] : [],
      timeout: 60000,
      gas: "auto",
      gasPrice: "auto"
    },

    // Local development (optional)
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    }
  },

  paths: {
    sources: "./contracts",
    tests: "./tests/unit",
    cache: "./cache",
    artifacts: "./artifacts"
  },

  mocha: {
    timeout: 120000 // 2 minutes for blockchain operations
  },

  // Gas reporter configuration (optional)
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    outputFile: "gas-report.txt",
    noColors: false,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY || undefined
  },

  // Contract size checker (optional)
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false
  }
};
