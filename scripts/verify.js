const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("\n🔍 Verifying WordleBountyEscrow on HashScan...\n");

  // Get network info
  const network = hre.network.name;
  console.log(`📡 Network: ${network}`);

  // Load deployment info
  const deploymentFile = path.join(__dirname, "..", "deployments", `${network}.json`);

  if (!fs.existsSync(deploymentFile)) {
    console.error(`❌ No deployment found for ${network}`);
    console.error(`   Please deploy first: pnpm run deploy:${network}`);
    process.exit(1);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentFile, "utf8"));
  const contractAddress = deployment.contractAddress;

  console.log(`📄 Contract Address: ${contractAddress}`);
  console.log(`⏳ Verifying contract...\n`);

  try {
    // Verify contract (no constructor arguments for WordleBountyEscrow)
    await hre.run("verify:verify", {
      address: contractAddress,
      constructorArguments: []
    });

    console.log("\n✅ Contract verified successfully!");

    const explorerUrl = network === "mainnet"
      ? `https://hashscan.io/mainnet/contract/${contractAddress}`
      : `https://hashscan.io/testnet/contract/${contractAddress}`;

    console.log(`\n🔗 View on HashScan: ${explorerUrl}\n`);

  } catch (error) {
    if (error.message.includes("Already Verified")) {
      console.log("✅ Contract already verified!");

      const explorerUrl = network === "mainnet"
        ? `https://hashscan.io/mainnet/contract/${contractAddress}`
        : `https://hashscan.io/testnet/contract/${contractAddress}`;

      console.log(`\n🔗 View on HashScan: ${explorerUrl}\n`);
    } else {
      console.error("\n❌ Verification failed:");
      console.error(error.message);
      console.log("\nℹ️  Manual verification:");
      console.log("   1. Flatten contract: pnpm run flatten");
      console.log("   2. Go to HashScan and upload flattened source");
      console.log("   3. Compiler: 0.8.19");
      console.log("   4. Optimization: enabled (200 runs)\n");
      process.exit(1);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
