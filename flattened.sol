[dotenv@17.2.3] injecting env (11) from .env -- tip: 🔐 prevent committing .env to code: https://dotenvx.com/precommit
// Sources flattened with hardhat v2.26.3 https://hardhat.org

// SPDX-License-Identifier: MIT

// File contracts/WordleBountyEscrow.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title WordleBountyEscrow
 * @dev Escrow contract for managing Wordle bounty lifecycle, HBAR deposits, and prize distribution
 * @notice Supports bounty creation, participation tracking, prize distribution with platform fees, and refunds
 */
contract WordleBountyEscrow {
    // Owner of the contract
    address public owner;

    // Platform fee in basis points (1 bps = 0.01%)
    uint256 public platformFeeBps = 250; // 2.5%
    uint256 public constant MAX_PLATFORM_FEE_BPS = 1000; // 10% maximum

    // Minimum bounty amount (1 HBAR = 100,000,000 tinybars)
    uint256 public constant MIN_BOUNTY_AMOUNT = 100000000; // 1 HBAR

    // Bounty status enum
    enum BountyStatus {
        Active,
        Completed,
        Cancelled,
        Expired
    }

    // Bounty struct
    struct Bounty {
        bytes32 bountyId;
        address creator;
        uint256 prizeAmount;
        uint256 deadline;
        bytes32 solutionHash;
        string metadata;
        address winner;
        bool isActive;
        bool isCompleted;
        uint256 participantCount;
        BountyStatus status;
    }

    // Storage
    mapping(bytes32 => Bounty) public bounties;
    mapping(bytes32 => mapping(address => bool)) public participants;
    mapping(bytes32 => address[]) public bountyParticipants;
    uint256 public accumulatedFees;
    bool public paused;

    // Events
    event BountyCreated(
        bytes32 indexed bountyId,
        address indexed creator,
        uint256 prizeAmount,
        uint256 deadline,
        bytes32 solutionHash
    );
    event ParticipantJoined(bytes32 indexed bountyId, address indexed participant);
    event BountyCompleted(
        bytes32 indexed bountyId,
        address indexed winner,
        uint256 netPrize,
        uint256 platformFee
    );
    event BountyCancelled(bytes32 indexed bountyId, address indexed creator);
    event BountyRefunded(bytes32 indexed bountyId, address indexed creator, uint256 amount);
    event PlatformFeeUpdated(uint256 newFeeBps);
    event FeesWithdrawn(address indexed owner, uint256 amount);
    event Paused(address indexed owner);
    event Unpaused(address indexed owner);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier bountyExists(bytes32 bountyId) {
        require(bounties[bountyId].creator != address(0), "Bounty does not exist");
        _;
    }

    modifier bountyActive(bytes32 bountyId) {
        require(bounties[bountyId].isActive, "Bounty is not active");
        require(!bounties[bountyId].isCompleted, "Bounty is already completed");
        _;
    }

    /**
     * @dev Constructor sets the contract deployer as owner
     */
    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Create a new bounty with HBAR deposit
     * @param bountyId Unique identifier for the bounty
     * @param solutionHash Hash of the correct word solution
     * @param deadline Unix timestamp when bounty expires
     * @param metadata IPFS or other metadata URI
     */
    function createBounty(
        bytes32 bountyId,
        bytes32 solutionHash,
        uint256 deadline,
        string calldata metadata
    ) external payable whenNotPaused {
        require(msg.value >= MIN_BOUNTY_AMOUNT, "Prize amount too small");
        require(bounties[bountyId].creator == address(0), "Bounty ID already exists");
        require(deadline > block.timestamp, "Deadline must be in the future");
        require(solutionHash != bytes32(0), "Solution hash required");

        bounties[bountyId] = Bounty({
            bountyId: bountyId,
            creator: msg.sender,
            prizeAmount: msg.value,
            deadline: deadline,
            solutionHash: solutionHash,
            metadata: metadata,
            winner: address(0),
            isActive: true,
            isCompleted: false,
            participantCount: 0,
            status: BountyStatus.Active
        });

        emit BountyCreated(bountyId, msg.sender, msg.value, deadline, solutionHash);
    }

    /**
     * @notice Join an active bounty as a participant
     * @param bountyId Identifier of the bounty to join
     */
    function joinBounty(bytes32 bountyId)
        external
        whenNotPaused
        bountyExists(bountyId)
        bountyActive(bountyId)
    {
        require(!participants[bountyId][msg.sender], "Already participating");
        require(block.timestamp < bounties[bountyId].deadline, "Bounty has expired");

        participants[bountyId][msg.sender] = true;
        bountyParticipants[bountyId].push(msg.sender);
        bounties[bountyId].participantCount++;

        emit ParticipantJoined(bountyId, msg.sender);
    }

    /**
     * @notice Complete a bounty and distribute prize to winner (owner only)
     * @param bountyId Identifier of the bounty
     * @param winnerAddress Address of the winner
     * @param solution Plaintext solution for verification
     */
    function completeBounty(
        bytes32 bountyId,
        address winnerAddress,
        string calldata solution
    ) external onlyOwner bountyExists(bountyId) bountyActive(bountyId) {
        // Verify solution matches hash
        bytes32 providedHash = keccak256(abi.encodePacked(solution));
        require(providedHash == bounties[bountyId].solutionHash, "Invalid solution");

        // Verify winner is a participant
        require(participants[bountyId][winnerAddress], "Winner is not a participant");

        Bounty storage bounty = bounties[bountyId];

        // Calculate prize and fee
        (uint256 netPrize, uint256 platformFee) = calculateNetPrize(bounty.prizeAmount);

        // Update bounty state
        bounty.isCompleted = true;
        bounty.isActive = false;
        bounty.winner = winnerAddress;
        bounty.status = BountyStatus.Completed;

        // Accumulate platform fee
        accumulatedFees += platformFee;

        // Transfer prize to winner
        (bool success, ) = winnerAddress.call{value: netPrize}("");
        require(success, "Prize transfer failed");

        emit BountyCompleted(bountyId, winnerAddress, netPrize, platformFee);
    }

    /**
     * @notice Cancel an active bounty and refund creator
     * @param bountyId Identifier of the bounty to cancel
     */
    function cancelBounty(bytes32 bountyId)
        external
        bountyExists(bountyId)
        bountyActive(bountyId)
    {
        Bounty storage bounty = bounties[bountyId];
        require(msg.sender == bounty.creator, "Only creator can cancel");
        require(bounty.participantCount == 0, "Cannot cancel with participants");

        bounty.isActive = false;
        bounty.status = BountyStatus.Cancelled;

        // Refund creator
        uint256 refundAmount = bounty.prizeAmount;
        bounty.prizeAmount = 0;

        (bool success, ) = bounty.creator.call{value: refundAmount}("");
        require(success, "Refund transfer failed");

        emit BountyCancelled(bountyId, msg.sender);
    }

    /**
     * @notice Claim refund for expired bounty with no winner
     * @param bountyId Identifier of the bounty
     */
    function claimExpiredBountyRefund(bytes32 bountyId)
        external
        bountyExists(bountyId)
        bountyActive(bountyId)
    {
        Bounty storage bounty = bounties[bountyId];
        require(msg.sender == bounty.creator, "Only creator can claim refund");
        require(block.timestamp >= bounty.deadline, "Bounty has not expired");

        bounty.isActive = false;
        bounty.status = BountyStatus.Expired;

        // Refund creator
        uint256 refundAmount = bounty.prizeAmount;
        bounty.prizeAmount = 0;

        (bool success, ) = bounty.creator.call{value: refundAmount}("");
        require(success, "Refund transfer failed");

        emit BountyRefunded(bountyId, msg.sender, refundAmount);
    }

    /**
     * @notice Update platform fee (owner only)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_PLATFORM_FEE_BPS, "Fee too high");
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(newFeeBps);
    }

    /**
     * @notice Withdraw accumulated platform fees (owner only)
     */
    function withdrawFees() external onlyOwner {
        uint256 amount = accumulatedFees;
        require(amount > 0, "No fees to withdraw");

        accumulatedFees = 0;

        (bool success, ) = owner.call{value: amount}("");
        require(success, "Fee withdrawal failed");

        emit FeesWithdrawn(owner, amount);
    }

    /**
     * @notice Pause contract (owner only)
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(owner);
    }

    /**
     * @notice Unpause contract (owner only)
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(owner);
    }

    /**
     * @notice Emergency withdraw all contract balance (owner only)
     * @dev Use only in case of emergency
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = owner.call{value: balance}("");
        require(success, "Emergency withdrawal failed");
    }

    /**
     * @notice Calculate net prize after platform fee
     * @param grossPrize Total prize amount
     * @return netPrize Amount winner receives
     * @return platformFee Amount platform receives
     */
    function calculateNetPrize(uint256 grossPrize)
        public
        view
        returns (uint256 netPrize, uint256 platformFee)
    {
        platformFee = (grossPrize * platformFeeBps) / 10000;
        netPrize = grossPrize - platformFee;
        return (netPrize, platformFee);
    }

    /**
     * @notice Get bounty details
     * @param bountyId Identifier of the bounty
     * @return Bounty struct
     */
    function getBounty(bytes32 bountyId) external view returns (Bounty memory) {
        return bounties[bountyId];
    }

    /**
     * @notice Check if address is a participant
     * @param bountyId Identifier of the bounty
     * @param participant Address to check
     * @return bool True if participant
     */
    function isParticipant(bytes32 bountyId, address participant) external view returns (bool) {
        return participants[bountyId][participant];
    }

    /**
     * @notice Get all participants for a bounty
     * @param bountyId Identifier of the bounty
     * @return Array of participant addresses
     */
    function getBountyParticipants(bytes32 bountyId) external view returns (address[] memory) {
        return bountyParticipants[bountyId];
    }

    /**
     * @notice Get contract balance
     * @return Contract HBAR balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Transfer ownership (owner only)
     * @param newOwner Address of new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        owner = newOwner;
    }

    /**
     * @dev Fallback function to reject direct HBAR transfers
     */
    receive() external payable {
        revert("Direct transfers not allowed");
    }
}
