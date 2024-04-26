import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  paths: {
    sources: "./contracts", // Directory containing your Solidity contracts
    tests: "./test", // Directory containing your test files
    cache: "./cache", // Directory for the compilation cache
    artifacts: "./artifacts" // Directory for compiled contract artifacts
  },
};

export default config;
