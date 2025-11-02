const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WordleBountyEscrow", function () {
  let escrowContract;
  let owner;
  let creator;
  let winner;
  let participant;

  // Test constants
  const MIN_BOUNTY = ethers.parseUnits("1", 8); // 1 HBAR = 100,000,000 tinybars
  const PRIZE_AMOUNT = ethers.parseUnits("10", 8); // 10 HBAR
  const BOUNTY_ID = ethers.encodeBytes32String("TEST_BOUNTY_001");
  const SOLUTION = "WORDLE";
  const SOLUTION_HASH = ethers.keccak256(ethers.toUtf8Bytes(SOLUTION));

  beforeEach(async function () {
    // Get signers
    [owner, creator, winner, participant] = await ethers.getSigners();

    // Deploy contract
    const WordleBountyEscrow = await ethers.getContractFactory("WordleBountyEscrow");
    escrowContract = await WordleBountyEscrow.deploy();
    await escrowContract.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the correct owner", async function () {
      expect(await escrowContract.owner()).to.equal(owner.address);
    });

    it("Should have correct initial platform fee", async function () {
      expect(await escrowContract.platformFeeBps()).to.equal(250); // 2.5%
    });

    it("Should have correct minimum bounty amount", async function () {
      expect(await escrowContract.MIN_BOUNTY_AMOUNT()).to.equal(MIN_BOUNTY);
    });
  });

  describe("Creating Bounties", function () {
    it("Should create a bounty with correct parameters", async function () {
      const deadline = Math.floor(Date.now() / 1000) + 86400; // 24 hours from now
      const metadata = "ipfs://QmTest123";

      await expect(
        escrowContract.connect(creator).createBounty(
          BOUNTY_ID,
          SOLUTION_HASH,
          deadline,
          metadata,
          { value: PRIZE_AMOUNT }
        )
      ).to.emit(escrowContract, "BountyCreated")
        .withArgs(BOUNTY_ID, creator.address, PRIZE_AMOUNT, deadline, SOLUTION_HASH);

      const bounty = await escrowContract.getBounty(BOUNTY_ID);
      expect(bounty.creator).to.equal(creator.address);
      expect(bounty.prizeAmount).to.equal(PRIZE_AMOUNT);
      expect(bounty.isActive).to.be.true;
      expect(bounty.isCompleted).to.be.false;
    });

    it("Should reject bounty with insufficient prize", async function () {
      const deadline = Math.floor(Date.now() / 1000) + 86400;
      const smallAmount = ethers.parseUnits("0.5", 8); // 0.5 HBAR

      await expect(
        escrowContract.connect(creator).createBounty(
          BOUNTY_ID,
          SOLUTION_HASH,
          deadline,
          "metadata",
          { value: smallAmount }
        )
      ).to.be.revertedWith("Prize amount too small");
    });

    it("Should reject duplicate bounty ID", async function () {
      const deadline = Math.floor(Date.now() / 1000) + 86400;

      await escrowContract.connect(creator).createBounty(
        BOUNTY_ID,
        SOLUTION_HASH,
        deadline,
        "metadata",
        { value: PRIZE_AMOUNT }
      );

      await expect(
        escrowContract.connect(creator).createBounty(
          BOUNTY_ID,
          SOLUTION_HASH,
          deadline,
          "metadata",
          { value: PRIZE_AMOUNT }
        )
      ).to.be.revertedWith("Bounty ID already exists");
    });
  });

  describe("Participating in Bounties", function () {
    beforeEach(async function () {
      const deadline = Math.floor(Date.now() / 1000) + 86400;
      await escrowContract.connect(creator).createBounty(
        BOUNTY_ID,
        SOLUTION_HASH,
        deadline,
        "metadata",
        { value: PRIZE_AMOUNT }
      );
    });

    it("Should allow users to join bounty", async function () {
      await expect(
        escrowContract.connect(participant).joinBounty(BOUNTY_ID)
      ).to.emit(escrowContract, "ParticipantJoined")
        .withArgs(BOUNTY_ID, participant.address);

      expect(await escrowContract.isParticipant(BOUNTY_ID, participant.address)).to.be.true;
    });

    it("Should prevent duplicate participation", async function () {
      await escrowContract.connect(participant).joinBounty(BOUNTY_ID);

      await expect(
        escrowContract.connect(participant).joinBounty(BOUNTY_ID)
      ).to.be.revertedWith("Already participating");
    });
  });

  describe("Completing Bounties", function () {
    beforeEach(async function () {
      const deadline = Math.floor(Date.now() / 1000) + 86400;
      await escrowContract.connect(creator).createBounty(
        BOUNTY_ID,
        SOLUTION_HASH,
        deadline,
        "metadata",
        { value: PRIZE_AMOUNT }
      );
      await escrowContract.connect(winner).joinBounty(BOUNTY_ID);
    });

    it("Should complete bounty and distribute prize", async function () {
      const initialBalance = await ethers.provider.getBalance(winner.address);

      await expect(
        escrowContract.connect(owner).completeBounty(
          BOUNTY_ID,
          winner.address,
          SOLUTION
        )
      ).to.emit(escrowContract, "BountyCompleted");

      const bounty = await escrowContract.getBounty(BOUNTY_ID);
      expect(bounty.isCompleted).to.be.true;
      expect(bounty.winner).to.equal(winner.address);

      // Check winner received prize (minus platform fee)
      const platformFee = (PRIZE_AMOUNT * 250n) / 10000n; // 2.5%
      const expectedPrize = PRIZE_AMOUNT - platformFee;
      const finalBalance = await ethers.provider.getBalance(winner.address);
      expect(finalBalance - initialBalance).to.be.closeTo(expectedPrize, ethers.parseUnits("0.01", 8));
    });

    it("Should reject completion with wrong solution", async function () {
      await expect(
        escrowContract.connect(owner).completeBounty(
          BOUNTY_ID,
          winner.address,
          "WRONG"
        )
      ).to.be.revertedWith("Invalid solution");
    });

    it("Should only allow owner to complete bounty", async function () {
      await expect(
        escrowContract.connect(creator).completeBounty(
          BOUNTY_ID,
          winner.address,
          SOLUTION
        )
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Cancelling and Refunds", function () {
    it("Should allow creator to cancel bounty with no participants", async function () {
      const deadline = Math.floor(Date.now() / 1000) + 86400;
      await escrowContract.connect(creator).createBounty(
        BOUNTY_ID,
        SOLUTION_HASH,
        deadline,
        "metadata",
        { value: PRIZE_AMOUNT }
      );

      const initialBalance = await ethers.provider.getBalance(creator.address);

      await expect(
        escrowContract.connect(creator).cancelBounty(BOUNTY_ID)
      ).to.emit(escrowContract, "BountyCancelled")
        .withArgs(BOUNTY_ID, creator.address);

      const bounty = await escrowContract.getBounty(BOUNTY_ID);
      expect(bounty.isActive).to.be.false;
    });

    it("Should refund expired bounty", async function () {
      const currentTime = Math.floor(Date.now() / 1000);
      const deadline = currentTime + 3600; // 1 hour from now
      await escrowContract.connect(creator).createBounty(
        BOUNTY_ID,
        SOLUTION_HASH,
        deadline,
        "metadata",
        { value: PRIZE_AMOUNT }
      );

      // Fast forward time past deadline using Hardhat network helpers
      await ethers.provider.send("evm_increaseTime", [3601]); // Move 1 hour + 1 second forward
      await ethers.provider.send("evm_mine", []); // Mine a new block

      await expect(
        escrowContract.connect(creator).claimExpiredBountyRefund(BOUNTY_ID)
      ).to.emit(escrowContract, "BountyRefunded")
        .withArgs(BOUNTY_ID, creator.address, PRIZE_AMOUNT);
    });
  });

  describe("Platform Fee Management", function () {
    it("Should allow owner to update platform fee", async function () {
      const newFee = 500; // 5%

      await expect(
        escrowContract.connect(owner).updatePlatformFee(newFee)
      ).to.emit(escrowContract, "PlatformFeeUpdated")
        .withArgs(newFee);

      expect(await escrowContract.platformFeeBps()).to.equal(newFee);
    });

    it("Should reject excessive platform fee", async function () {
      const excessiveFee = 1001; // 10.01%

      await expect(
        escrowContract.connect(owner).updatePlatformFee(excessiveFee)
      ).to.be.revertedWith("Fee too high");
    });

    it("Should calculate correct net prize", async function () {
      const result = await escrowContract.calculateNetPrize(PRIZE_AMOUNT);
      const expectedFee = (PRIZE_AMOUNT * 250n) / 10000n; // 2.5%
      const expectedNetPrize = PRIZE_AMOUNT - expectedFee;

      expect(result.netPrize).to.equal(expectedNetPrize);
      expect(result.platformFee).to.equal(expectedFee);
    });
  });
});