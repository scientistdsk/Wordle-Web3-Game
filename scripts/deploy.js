const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("\n🚀 Deploying WordleBountyEscrow to Hedera Network...\n");

  // Get network info
  const network = hre.network.name;
  const chainId = hre.network.config.chainId;
  console.log(`📡 Network: ${network} (Chain ID: ${chainId})`);

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log(`🔑 Deployer address: ${deployer.address}`);

  // Check deployer balance
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  const balanceHBAR = hre.ethers.formatUnits(balance, 18);
  console.log(`💰 Deployer balance: ${balanceHBAR} HBAR\n`);

  if (parseFloat(balanceHBAR) < 10) {
    console.warn("⚠️  Warning: Low balance. Get test HBAR from https://portal.hedera.com/faucet\n");
  }

  // Deploy contract
  console.log("📝 Deploying WordleBountyEscrow contract...");
  const WordleBountyEscrow = await hre.ethers.getContractFactory("WordleBountyEscrow");

  const escrow = await WordleBountyEscrow.deploy();
  await escrow.waitForDeployment();

  const contractAddress = await escrow.getAddress();
  console.log(`✅ WordleBountyEscrow deployed to: ${contractAddress}`);

  // Get deployment transaction
  const deployTx = escrow.deploymentTransaction();
  console.log(`📄 Deployment transaction: ${deployTx?.hash}`);

  // Wait for confirmations
  console.log("⏳ Waiting for confirmations...");
  await deployTx?.wait(2); // Wait for 2 confirmations
  console.log("✅ Confirmed!\n");

  // Verify contract parameters
  console.log("🔍 Verifying contract parameters:");
  const owner = await escrow.owner();
  const platformFee = await escrow.platformFeeBps();
  const minBounty = await escrow.MIN_BOUNTY_AMOUNT();
  const minBountyHBAR = hre.ethers.formatUnits(minBounty, 8); // tinybars to HBAR

  console.log(`   Owner: ${owner}`);
  console.log(`   Platform Fee: ${Number(platformFee) / 100}%`);
  console.log(`   Min Bounty: ${minBountyHBAR} HBAR\n`);

  // Save deployment info
  const deploymentInfo = {
    network: network,
    chainId: chainId,
    contractAddress: contractAddress,
    deployerAddress: deployer.address,
    deploymentTx: deployTx?.hash,
    timestamp: new Date().toISOString(),
    blockNumber: deployTx?.blockNumber,
    owner: owner,
    platformFeeBps: platformFee.toString(),
    minBountyAmount: minBounty.toString()
  };

  // Create deployments directory if it doesn't exist
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir);
  }

  // Save network-specific deployment
  const deploymentFile = path.join(deploymentsDir, `${network}.json`);
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
  console.log(`💾 Deployment info saved to: deployments/${network}.json\n`);

  // Update deployment history
  const historyFile = path.join(deploymentsDir, "history.json");
  let history = [];
  if (fs.existsSync(historyFile)) {
    history = JSON.parse(fs.readFileSync(historyFile, "utf8"));
  }
  history.push(deploymentInfo);
  fs.writeFileSync(historyFile, JSON.stringify(history, null, 2));

  // Print instructions
  console.log("=" .repeat(80));
  console.log("🎉 DEPLOYMENT SUCCESSFUL!");
  console.log("=" .repeat(80));
  console.log("\n📋 Next Steps:\n");
  console.log("1. Add to .env.local:");
  console.log(`   VITE_ESCROW_CONTRACT_ADDRESS=${contractAddress}\n`);
  console.log("2. Verify contract on HashScan:");
  console.log(`   pnpm run verify:${network}\n`);
  console.log("3. View on HashScan:");
  const explorerUrl = network === "mainnet"
    ? `https://hashscan.io/mainnet/contract/${contractAddress}`
    : `https://hashscan.io/testnet/contract/${contractAddress}`;
  console.log(`   ${explorerUrl}\n`);
  console.log("=" .repeat(80) + "\n");
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
