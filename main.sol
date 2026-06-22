// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Signed sealed-bid auction
/// @notice Educational example:
///         1. A bidder creates a private commitment.
///         2. The bidder signs authorization for that commitment.
///         3. Any relayer can submit the signed commitment.
///         4. The bidder reveals the bid and deposits ETH.
///         5. Losing bidders can withdraw their ETH.
contract SignedSealedBidAuction {
    address public immutable seller;

    uint256 public immutable commitEnd;
    uint256 public immutable revealEnd;

    bytes32 public immutable auctionId;

    address public highestBidder;
    uint256 public highestBid;

    bool public finalized;
    bool private withdrawalLocked;

    struct StoredCommitment {
        bytes32 value;
        uint256 nonce;
        bool revealed;
    }

    // Bidder => latest commitment
    mapping(address => StoredCommitment) public commitments;

    // Bidder => next valid signature nonce
    mapping(address => uint256) public nonces;

    // Refunds and seller proceeds
    mapping(address => uint256) public credits;

    bytes32 public constant COMMIT_AUTHORIZATION_TYPEHASH =
        keccak256(
            "CommitAuthorization(bytes32 auctionId,address bidder,bytes32 commitment,uint256 nonce,uint256 deadline,address verifyingContract,uint256 chainId)"
        );

    // Half of the secp256k1 curve order.
    // Requiring a low-s signature prevents signature malleability.
    uint256 private constant SECP256K1_HALF_ORDER =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    event BidCommitted(
        address indexed bidder,
        bytes32 indexed commitment,
        uint256 nonce,
        address indexed relayer
    );

    event BidRevealed(
        address indexed bidder,
        uint256 amount,
        bool isHighest
    );

    event AuctionFinalized(
        address indexed winner,
        uint256 winningBid
    );

    event Withdrawal(
        address indexed account,
        uint256 amount
    );

    constructor(
        uint256 commitDurationSeconds,
        uint256 revealDurationSeconds
    ) {
        require(
            commitDurationSeconds > 0,
            "Commit duration is zero"
        );

        require(
            revealDurationSeconds > 0,
            "Reveal duration is zero"
        );

        seller = msg.sender;

        commitEnd =
            block.timestamp +
            commitDurationSeconds;

        revealEnd =
            commitEnd +
            revealDurationSeconds;

        auctionId = keccak256(
            abi.encode(
                address(this),
                block.chainid,
                msg.sender,
                block.timestamp,
                commitEnd,
                revealEnd
            )
        );
    }

    /// @notice Creates the commitment for a private bid.
    /// @param bidder Address that will reveal the bid.
    /// @param bidAmount Bid amount in wei.
    /// @param salt Secret random bytes32 value.
    function makeCommitment(
        address bidder,
        uint256 bidAmount,
        bytes32 salt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                auctionId,
                address(this),
                block.chainid,
                bidder,
                bidAmount,
                salt
            )
        );
    }

    /// @notice Returns the value the bidder signs off-chain.
    /// @dev Sign this result with personal_sign or ethers.signMessage().
    function getCommitAuthorizationHash(
        address bidder,
        bytes32 commitment,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                COMMIT_AUTHORIZATION_TYPEHASH,
                auctionId,
                bidder,
                commitment,
                nonce,
                deadline,
                address(this),
                block.chainid
            )
        );
    }

    /// @notice Returns the prefixed digest used by ecrecover.
    function getCommitAuthorizationDigest(
        address bidder,
        bytes32 commitment,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 authorizationHash =
            getCommitAuthorizationHash(
                bidder,
                commitment,
                nonce,
                deadline
            );

        return keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                authorizationHash
            )
        );
    }

    /// @notice Submits a signed commitment.
    /// @dev The transaction sender may be the bidder or a relayer.
    function commitBid(
        address bidder,
        bytes32 commitment,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(
            block.timestamp < commitEnd,
            "Commit phase ended"
        );

        require(
            block.timestamp <= deadline,
            "Signature expired"
        );

        require(
            bidder != address(0),
            "Invalid bidder"
        );

        require(
            commitment != bytes32(0),
            "Empty commitment"
        );

        require(
            nonce == nonces[bidder],
            "Invalid nonce"
        );

        bytes32 digest =
            getCommitAuthorizationDigest(
                bidder,
                commitment,
                nonce,
                deadline
            );

        address recoveredSigner =
            _recoverSigner(digest, signature);

        require(
            recoveredSigner == bidder,
            "Invalid signature"
        );

        // Consume the nonce before storing the commitment.
        nonces[bidder] = nonce + 1;

        // A bidder can replace their commitment during the commit phase
        // by signing another commitment with the next nonce.
        commitments[bidder] = StoredCommitment({
            value: commitment,
            nonce: nonce,
            revealed: false
        });

        emit BidCommitted(
            bidder,
            commitment,
            nonce,
            msg.sender
        );
    }

    /// @notice Reveals the bid and deposits exactly bidAmount wei.
    function revealBid(
        uint256 bidAmount,
        bytes32 salt
    ) external payable {
        require(
            block.timestamp >= commitEnd,
            "Reveal phase not started"
        );

        require(
            block.timestamp < revealEnd,
            "Reveal phase ended"
        );

        require(
            msg.value == bidAmount,
            "Wrong ETH amount"
        );

        StoredCommitment storage stored =
            commitments[msg.sender];

        require(
            stored.value != bytes32(0),
            "No commitment"
        );

        require(
            !stored.revealed,
            "Already revealed"
        );

        bytes32 expectedCommitment =
            makeCommitment(
                msg.sender,
                bidAmount,
                salt
            );

        require(
            expectedCommitment == stored.value,
            "Commitment mismatch"
        );

        stored.revealed = true;

        bool isHighest =
            bidAmount > highestBid;

        if (isHighest) {
            // Refund the previous highest bidder.
            if (highestBidder != address(0)) {
                credits[highestBidder] += highestBid;
            }

            highestBidder = msg.sender;
            highestBid = bidAmount;
        } else {
            // Equal bids lose to the bid revealed first.
            credits[msg.sender] += bidAmount;
        }

        emit BidRevealed(
            msg.sender,
            bidAmount,
            isHighest
        );
    }

    /// @notice Finishes the auction after the reveal period.
    /// @dev Anyone can finalize, but only the seller receives the proceeds.
    function finalize() external {
        require(
            block.timestamp >= revealEnd,
            "Reveal phase not ended"
        );

        require(
            !finalized,
            "Already finalized"
        );

        finalized = true;

        if (highestBid > 0) {
            credits[seller] += highestBid;
        }

        emit AuctionFinalized(
            highestBidder,
            highestBid
        );
    }

    /// @notice Withdraws refunds or seller proceeds.
    function withdraw() external {
        require(
            !withdrawalLocked,
            "Reentrant call"
        );

        uint256 amount =
            credits[msg.sender];

        require(
            amount > 0,
            "Nothing to withdraw"
        );

        withdrawalLocked = true;

        // Update state before transferring ETH.
        credits[msg.sender] = 0;

        (bool success, ) =
            payable(msg.sender).call{
                value: amount
            }("");

        require(
            success,
            "ETH transfer failed"
        );

        withdrawalLocked = false;

        emit Withdrawal(
            msg.sender,
            amount
        );
    }

    /// @notice Returns the current auction phase.
    function phase()
        external
        view
        returns (string memory)
    {
        if (block.timestamp < commitEnd) {
            return "COMMIT";
        }

        if (block.timestamp < revealEnd) {
            return "REVEAL";
        }

        if (!finalized) {
            return "READY_TO_FINALIZE";
        }

        return "FINALIZED";
    }

    function _recoverSigner(
        bytes32 digest,
        bytes calldata signature
    ) internal pure returns (address) {
        require(
            signature.length == 65,
            "Signature must be 65 bytes"
        );

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(
                add(signature.offset, 32)
            )
            v := byte(
                0,
                calldataload(
                    add(signature.offset, 64)
                )
            )
        }

        // Some libraries return 0 or 1 instead of 27 or 28.
        if (v < 27) {
            v += 27;
        }

        require(
            v == 27 || v == 28,
            "Invalid signature v"
        );

        require(
            uint256(s) > 0 &&
                uint256(s) <= SECP256K1_HALF_ORDER,
            "Invalid signature s"
        );

        address recovered =
            ecrecover(
                digest,
                v,
                r,
                s
            );

        require(
            recovered != address(0),
            "Signature recovery failed"
        );

        return recovered;
    }

    receive() external payable {
        revert("Use revealBid");
    }
}