// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * AI-SES Smart Escrow Contract
 * ─────────────────────────────────────────────────────────────────────────────
 * This contract holds cryptocurrency in escrow based on an AI-generated
 * fraud risk score. Three outcomes are possible:
 *
 *   LOW  RISK (score < 0.30) → funds released immediately to receiver
 *   MED  RISK (0.30 – 0.70) → funds held 24 hours for manual review
 *   HIGH RISK (score > 0.70) → transaction rejected, funds refunded to sender
 *
 * Deployed on: Ethereum Goerli Testnet
 * ─────────────────────────────────────────────────────────────────────────────
 */

// OpenZeppelin ReentrancyGuard (prevents re-entrancy attacks like the DAO hack)
abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;
    uint256 private _status;
    constructor() { _status = NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != ENTERED, "ReentrancyGuard: reentrant call");
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }
}

contract AISmartEscrow is ReentrancyGuard {

    // ─── Risk thresholds (stored as integers: 30 = 0.30, 70 = 0.70) ──────────
    uint256 public constant ALPHA = 30;   // Low/Medium boundary
    uint256 public constant BETA  = 70;   // Medium/High boundary

    // Review window: 24 hours in seconds
    uint256 public constant REVIEW_WINDOW = 24 hours;

    // ─── Escrow record ────────────────────────────────────────────────────────
    enum RiskLevel { Low, Medium, High }
    enum TxStatus  { Pending, Released, Held, Rejected, Refunded, Approved }

    struct EscrowTx {
        address payable sender;
        address payable receiver;
        uint256 amount;
        uint256 riskScore;      // 0–100 (e.g. 47 = risk score 0.47)
        RiskLevel riskLevel;
        TxStatus  status;
        uint256   createdAt;
    }

    mapping(bytes32 => EscrowTx) public escrows;
    address public owner;
    address public reviewer;    // authorised to approve/reject medium-risk txns

    // ─── Events (emitted on-chain for transparency) ───────────────────────────
    event TransactionDeposited(bytes32 indexed txId, address sender,
                               address receiver, uint256 amount, uint256 riskScore,
                               RiskLevel level);
    event TransactionReleased (bytes32 indexed txId, address receiver, uint256 amount);
    event TransactionHeld     (bytes32 indexed txId, uint256 reviewDeadline);
    event TransactionRejected (bytes32 indexed txId, address sender, uint256 refund);
    event TransactionApproved (bytes32 indexed txId, address reviewer);

    // ─── Modifiers ────────────────────────────────────────────────────────────
    modifier onlyOwner()    { require(msg.sender == owner,    "Not owner");    _; }
    modifier onlyReviewer() { require(msg.sender == reviewer || msg.sender == owner,
                                      "Not reviewer"); _; }

    constructor(address _reviewer) {
        owner    = msg.sender;
        reviewer = _reviewer;
    }

    // ─── STAGE 7: Deposit funds into escrow ───────────────────────────────────
    /**
     * @param receiver   Intended recipient of the funds
     * @param riskScore  0-100 integer from the off-chain ML model (47 = 0.47)
     *
     * Called by the AI-SES client after the ML engine returns a risk score.
     * Funds are held in this contract — NOT sent to receiver yet.
     */
    function depositFunds(address payable receiver, uint256 riskScore)
        external payable nonReentrant returns (bytes32 txId)
    {
        require(msg.value > 0,        "No ETH sent");
        require(receiver != address(0),"Invalid receiver");
        require(riskScore <= 100,     "Score must be 0-100");

        // Generate unique transaction ID
        txId = keccak256(abi.encodePacked(
            msg.sender, receiver, msg.value, riskScore, block.timestamp
        ));
        require(escrows[txId].createdAt == 0, "Duplicate transaction");

        // ─── STAGE 8: Decision Engine ─────────────────────────────────────────
        RiskLevel level;
        TxStatus  status;

        if (riskScore < ALPHA) {
            // LOW RISK → release immediately
            level  = RiskLevel.Low;
            status = TxStatus.Released;
        } else if (riskScore < BETA) {
            // MEDIUM RISK → hold for review
            level  = RiskLevel.Medium;
            status = TxStatus.Held;
        } else {
            // HIGH RISK → reject immediately
            level  = RiskLevel.High;
            status = TxStatus.Rejected;
        }

        // Store escrow record (checks-effects-interactions pattern)
        escrows[txId] = EscrowTx({
            sender:    payable(msg.sender),
            receiver:  receiver,
            amount:    msg.value,
            riskScore: riskScore,
            riskLevel: level,
            status:    status,
            createdAt: block.timestamp
        });

        emit TransactionDeposited(txId, msg.sender, receiver, msg.value, riskScore, level);

        // Execute the decision
        if (level == RiskLevel.Low) {
            _releaseFunds(txId);

        } else if (level == RiskLevel.Medium) {
            uint256 deadline = block.timestamp + REVIEW_WINDOW;
            emit TransactionHeld(txId, deadline);

        } else {
            _refundSender(txId);
        }

        return txId;
    }

    // ─── Reviewer: approve a medium-risk transaction ──────────────────────────
    function approveHeldTransaction(bytes32 txId)
        external onlyReviewer nonReentrant
    {
        EscrowTx storage tx_ = escrows[txId];
        require(tx_.status    == TxStatus.Held,   "Not in held state");
        require(tx_.riskLevel == RiskLevel.Medium, "Not a medium-risk tx");

        tx_.status = TxStatus.Approved;
        emit TransactionApproved(txId, msg.sender);
        _releaseFunds(txId);
    }

    // ─── Reviewer: reject a medium-risk transaction ───────────────────────────
    function rejectHeldTransaction(bytes32 txId)
        external onlyReviewer nonReentrant
    {
        EscrowTx storage tx_ = escrows[txId];
        require(tx_.status    == TxStatus.Held,   "Not in held state");
        require(tx_.riskLevel == RiskLevel.Medium, "Not a medium-risk tx");

        _refundSender(txId);
    }

    // ─── Auto-refund after review window expires (anyone can call) ────────────
    function claimExpiredRefund(bytes32 txId) external nonReentrant {
        EscrowTx storage tx_ = escrows[txId];
        require(tx_.status == TxStatus.Held, "Not in held state");
        require(block.timestamp > tx_.createdAt + REVIEW_WINDOW, "Window not expired");

        _refundSender(txId);
    }

    // ─── Internal: release funds to receiver ─────────────────────────────────
    function _releaseFunds(bytes32 txId) internal {
        EscrowTx storage tx_ = escrows[txId];
        tx_.status = TxStatus.Released;
        uint256 amount = tx_.amount;

        // Interactions last (checks-effects-interactions)
        (bool ok,) = tx_.receiver.call{value: amount}("");
        require(ok, "Transfer failed");

        emit TransactionReleased(txId, tx_.receiver, amount);
    }

    // ─── Internal: refund funds to sender ────────────────────────────────────
    function _refundSender(bytes32 txId) internal {
        EscrowTx storage tx_ = escrows[txId];
        tx_.status = TxStatus.Refunded;
        uint256 amount = tx_.amount;

        (bool ok,) = tx_.sender.call{value: amount}("");
        require(ok, "Refund failed");

        emit TransactionRejected(txId, tx_.sender, amount);
    }

    // ─── View: check status of any transaction ───────────────────────────────
    function getTransaction(bytes32 txId)
        external view returns (
            address sender, address receiver, uint256 amount,
            uint256 riskScore, RiskLevel level, TxStatus status
        )
    {
        EscrowTx storage tx_ = escrows[txId];
        return (tx_.sender, tx_.receiver, tx_.amount,
                tx_.riskScore, tx_.riskLevel, tx_.status);
    }

    // ─── View: decode risk level for front-end display ────────────────────────
    function getRiskLabel(uint256 score) external pure returns (string memory) {
        if (score < ALPHA) return "LOW - funds will be released immediately";
        if (score < BETA)  return "MEDIUM - funds held 24h for review";
        return "HIGH - transaction will be rejected and refunded";
    }

    receive() external payable { revert("Use depositFunds()"); }
}
