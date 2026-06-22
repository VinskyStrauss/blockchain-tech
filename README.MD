# Signed Sealed-Bid Auction

A simple educational Ethereum auction built with Solidity and tested entirely in Remix IDE.

The project uses:

- a **commit–reveal scheme** to hide bids during the commitment phase;
- an **off-chain signature** to prove that the bidder authorized the commitment;
- Remix VM accounts for local testing;
- ETH escrow for revealed bids;
- withdrawals for losing bidders and the seller.

> One deployment of `main.sol` represents one auction.

## Project Files

```text
.
├── main.sol
└── scripts
    ├── BidPlacement.js
    └── BidReveal.js
```

### `main.sol`

Contains the `SignedSealedBidAuction` smart contract.

The contract manages:

- the seller;
- commitment and reveal deadlines;
- signed bid commitments;
- bid reveals;
- the current highest bid;
- auction finalization;
- bidder refunds;
- seller withdrawals.

### `scripts/BidPlacement.js`

Creates and signs a bid commitment, then submits it to the contract.

The script:

1. connects to the selected Remix VM;
2. loads the bidder account;
3. creates a commitment from the bidder, bid amount, and salt;
4. reads the bidder's current nonce;
5. creates the authorization hash;
6. signs the hash;
7. verifies the recovered signer;
8. calls `commitBid()`.

### `scripts/BidReveal.js`

Reveals the previously committed bid.

The script checks the current auction phase before sending the transaction. When the auction is still in the `COMMIT` phase, the queued version waits until the reveal phase begins and then submits `revealBid()` automatically.

The Remix tab must remain open while the script is waiting.

## Auction Phases

The contract exposes a `phase()` function that returns one of the following values:

| Phase | Meaning |
|---|---|
| `COMMIT` | Bidders can submit signed commitments. |
| `REVEAL` | Bidders can reveal their bids and deposit ETH. |
| `READY_TO_FINALIZE` | The reveal period has ended and `finalize()` can be called. |
| `FINALIZED` | The auction has been finalized. |

The phase is calculated from the current block timestamp.

## Requirements

- Remix IDE
- Solidity compiler `0.8.24` or newer
- Remix VM
- JavaScript scripts enabled in Remix
- No external frontend is required

The JavaScript examples use ethers.js v5 syntax.

## Deploying the Contract

1. Open Remix IDE.
2. Create or open `main.sol`.
3. Compile the contract using Solidity `0.8.24` or newer.
4. Open **Deploy & Run Transactions**.
5. Select a Remix VM environment.
6. Select the account that will act as the seller.
7. Enter the constructor parameters.

Example:

```text
commitDurationSeconds: 300
revealDurationSeconds: 300
```

This creates:

- a 5-minute commitment phase;
- a 5-minute reveal phase.

8. Click **Deploy**.
9. Copy the deployed contract address.

Do not reset or change the Remix VM after deployment. Doing so will remove or replace the deployed contract state.

## Configure `BidPlacement.js`

Update the configuration values near the beginning of the script:

```javascript
const contractAddress =
    "PASTE_DEPLOYED_CONTRACT_ADDRESS";

const bidderAddress =
    "PASTE_REMIX_VM_BIDDER_ADDRESS";

const bidAmount =
    ethers.utils.parseEther("1");

const salt =
    "0x8f3a6d9c41e7b2f05c8d13a964be27f1d5c7048a9e6b32f0c147da85b39e62ac";
```

The example bid is `1 ETH`.

The salt must be exactly 32 bytes and must remain secret until the reveal phase.

Store the following values safely:

- bidder address;
- bid amount;
- salt;
- deployed contract address.

Changing any of these values before revealing will cause a commitment mismatch.

## Place a Bid

1. Confirm that `phase()` returns:

```text
COMMIT
```

2. Make sure `BidPlacement.js` contains the correct:
   - contract address;
   - bidder address;
   - bid amount;
   - salt.

3. Right-click `BidPlacement.js`.
4. Select **Run**.
5. Check the Remix terminal.

A successful run should print information similar to:

```text
Bidder: 0x...
Bid amount: 1000000000000000000
Salt: 0x...
Commitment: 0x...
Nonce: 0
Signature: 0x...
Commitment submitted successfully
```

The commitment hides the bid amount because only the hash is stored during the commit phase.

## Reveal a Bid

The reveal must use:

- the same bidder account;
- the same bid amount;
- the same salt;
- the same deployed contract.

Configure `BidReveal.js` with the same values used in `BidPlacement.js`:

```javascript
const contractAddress =
    "PASTE_DEPLOYED_CONTRACT_ADDRESS";

const bidderAddress =
    "PASTE_REMIX_VM_BIDDER_ADDRESS";

const bidAmount =
    ethers.utils.parseEther("1");

const salt =
    "0x8f3a6d9c41e7b2f05c8d13a964be27f1d5c7048a9e6b32f0c147da85b39e62ac";
```

Then:

1. Right-click `BidReveal.js`.
2. Select **Run**.
3. Leave Remix open if the script is waiting for the reveal phase.
4. Watch the Remix terminal.

When the contract enters the reveal phase, the script calls:

```javascript
contract.revealBid(
    bidAmount,
    salt,
    {
        value: bidAmount
    }
);
```

The ETH value sent with the transaction must equal the revealed bid amount.

A successful reveal should print information similar to:

```text
Current phase: REVEAL
Stored commitment: 0x...
Expected commitment: 0x...
Submitting reveal for 1.0 ETH
Reveal confirmed in block: ...
Highest bidder: 0x...
Highest bid: 1.0 ETH
```

## Finalize the Auction

After the reveal period ends, call:

```solidity
finalize()
```

Anyone can call `finalize()`, but the winning bid is credited only to the seller.

Before finalizing, `phase()` should return:

```text
READY_TO_FINALIZE
```

After finalizing, it should return:

```text
FINALIZED
```

## Withdraw Funds

The contract uses a pull-payment pattern. ETH is credited to the `credits` mapping and must be withdrawn manually.

### Losing bidder

A losing bidder calls:

```solidity
withdraw()
```

This returns the bidder's revealed ETH.

### Previous highest bidder

When a higher bid is revealed, the previous highest bidder receives a refundable credit and can call:

```solidity
withdraw()
```

### Seller

After `finalize()`, the seller calls:

```solidity
withdraw()
```

This transfers the winning bid to the seller.

You can inspect a pending balance with:

```solidity
credits(address)
```

## Useful Contract Functions

| Function | Purpose |
|---|---|
| `phase()` | Returns the current auction phase. |
| `commitEnd()` | Returns the commitment deadline as a Unix timestamp. |
| `revealEnd()` | Returns the reveal deadline as a Unix timestamp. |
| `makeCommitment()` | Calculates the commitment for a bidder, amount, and salt. |
| `nonces(address)` | Returns the bidder's next signature nonce. |
| `commitments(address)` | Returns the stored commitment, nonce, and reveal status. |
| `highestBidder()` | Returns the current highest bidder. |
| `highestBid()` | Returns the current highest bid in wei. |
| `credits(address)` | Returns the amount an address can withdraw. |
| `finalized()` | Shows whether the auction has been finalized. |

## Complete Test Flow

### 1. Deploy

Deploy `main.sol` with short test durations, for example:

```text
120
120
```

This gives two minutes for commitments and two minutes for reveals.

### 2. Bidder A commits

Configure and run `BidPlacement.js` using:

```text
Bid: 1 ETH
```

### 3. Bidder B commits

Change the bidder address, amount, and salt, then run the script again:

```text
Bid: 2 ETH
```

Each bidder should use a different salt.

### 4. Reveal both bids

Run `BidReveal.js` separately for each bidder using the exact original values.

Bidder B should become the highest bidder.

### 5. Finalize

Wait until `phase()` returns `READY_TO_FINALIZE`, then call:

```solidity
finalize()
```

### 6. Withdraw

- Bidder A calls `withdraw()` to recover the losing bid.
- The seller calls `withdraw()` to receive the winning bid.

## Important Notes

### Keep the salt private

The salt prevents another user from guessing the bid from its commitment. Do not publish it during the commitment phase.

### Keep the reveal values unchanged

A commitment depends on:

```text
auction ID
contract address
chain ID
bidder address
bid amount
salt
```

Any mismatch causes `revealBid()` to revert.

### Use the same Remix VM

The deployed contract and Remix accounts belong to the selected Remix VM environment. Resetting the VM removes the auction state.

### Keep Remix open for queued reveals

`BidReveal.js` cannot schedule a transaction inside the blockchain. It waits locally in the Remix browser tab and sends the reveal when the phase changes.

If Remix is closed, refreshed, or disconnected, the queued reveal will not be submitted.

### One contract per auction

Every deployment creates a new auction with:

- a new seller;
- new deadlines;
- a new auction ID;
- separate commitments;
- separate balances.

## Security and Educational Use

This project is intended for education and local testing.

It has not been professionally audited and should not be used with real funds without further review and testing.

Possible production improvements include:

- EIP-712 typed-data signatures;
- penalties for bidders who do not reveal;
- minimum bids;
- reserve prices;
- explicit tie-breaking rules;
- cancellation handling;
- automated tests;
- deployment scripts;
- stronger access-control and emergency procedures.

## License

MIT
