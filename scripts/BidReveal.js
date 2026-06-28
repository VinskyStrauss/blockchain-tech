const { ethers } = require("ethers");

const sleep = (milliseconds) =>
    new Promise((resolve) =>
        setTimeout(resolve, milliseconds)
    );

(async () => {
    try {
        /*
         * CONFIGURATION
         */

        const contractAddress =
            "PASTE CONTRACT ADDRESS";

        // Same bidder used in SignAndCommit.
        const bidderAddress =
            "PASTE ACCOUNT ADDRESS";

        // Same amount used when creating the commitment.
        const bidAmount =
            ethers.utils.parseEther("2");

        // Same salt used when creating the commitment.
        const salt =
            "0x8f3a6d9c41e7b2f05c8d13a964be27f1d5c7048a9e6b32f0c147da85b39e62ac";

        const abi = [
            "function phase() view returns (string)",
            "function commitEnd() view returns (uint256)",
            "function revealEnd() view returns (uint256)",
            "function commitments(address) view returns (bytes32 value, uint256 nonce, bool revealed)",
            "function makeCommitment(address bidder, uint256 bidAmount, bytes32 salt) view returns (bytes32)",
            "function revealBid(uint256 bidAmount, bytes32 salt) payable",
            "function highestBidder() view returns (address)",
            "function highestBid() view returns (uint256)"
        ];

        const provider =
            new ethers.providers.Web3Provider(
                web3Provider
            );

        const signer =
            provider.getSigner(bidderAddress);

        const actualSignerAddress =
            await signer.getAddress();

        if (
            actualSignerAddress.toLowerCase() !==
            bidderAddress.toLowerCase()
        ) {
            throw new Error(
                "Selected signer does not match bidderAddress."
            );
        }

        const contract =
            new ethers.Contract(
                contractAddress,
                abi,
                signer
            );

        /*
         * CHECK THE STORED COMMITMENT
         */

        const stored =
            await contract.commitments(
                bidderAddress
            );

        const storedCommitment = stored[0];
        const alreadyRevealed = stored[2];

        if (
            storedCommitment ===
            ethers.constants.HashZero
        ) {
            throw new Error(
                "No commitment exists for this bidder."
            );
        }

        if (alreadyRevealed) {
            console.log(
                "This bidder has already revealed."
            );

            return;
        }

        const expectedCommitment =
            await contract.makeCommitment(
                bidderAddress,
                bidAmount,
                salt
            );

        console.log(
            "Stored commitment:",
            storedCommitment
        );

        console.log(
            "Expected commitment:",
            expectedCommitment
        );

        if (
            storedCommitment.toLowerCase() !==
            expectedCommitment.toLowerCase()
        ) {
            throw new Error(
                "Commitment mismatch. Check bidder, bid amount, and salt."
            );
        }

        /*
         * CHECK THE CURRENT PHASE
         */

        const currentPhase =
            await contract.phase();

        console.log(
            "Current phase:",
            currentPhase
        );

        if (currentPhase === "FINALIZED") {
            console.log(
                "Auction is already finalized."
            );

            return;
        }

        if (
            currentPhase ===
            "READY_TO_FINALIZE"
        ) {
            console.log(
                "The reveal phase has already ended."
            );

            return;
        }

        const commitEnd =
            (await contract.commitEnd()).toNumber();

        const revealEnd =
            (await contract.revealEnd()).toNumber();

        const initialBlock =
            await provider.getBlock("latest");

        const scriptStartedAt =
            Date.now();

        /*
         * QUEUE THE REVEAL
         */

        if (currentPhase === "COMMIT") {
            // Two-second safety buffer after commitEnd.
            const secondsToWait =
                Math.max(
                    commitEnd -
                        initialBlock.timestamp +
                        2,
                    0
                );

            console.log(
                "Reveal queued."
            );

            console.log(
                "Seconds until reveal:",
                secondsToWait
            );

            const targetTime =
                Date.now() +
                secondsToWait * 1000;

            while (Date.now() < targetTime) {
                const remainingSeconds =
                    Math.ceil(
                        (
                            targetTime -
                            Date.now()
                        ) / 1000
                    );

                console.log(
                    "Reveal starts in approximately",
                    remainingSeconds,
                    "seconds"
                );

                // Report at most once every 10 seconds.
                const sleepTime =
                    Math.min(
                        10000,
                        targetTime -
                            Date.now()
                    );

                if (sleepTime > 0) {
                    await sleep(sleepTime);
                }
            }
        } else if (
            currentPhase !== "REVEAL"
        ) {
            throw new Error(
                "Unknown phase: " +
                currentPhase
            );
        }

        /*
         * CHECK WHETHER THE SCRIPT WOKE UP TOO LATE
         */

        const elapsedSeconds =
            Math.floor(
                (
                    Date.now() -
                    scriptStartedAt
                ) / 1000
            );

        const estimatedChainTimestamp =
            initialBlock.timestamp +
            elapsedSeconds;

        if (
            estimatedChainTimestamp >=
            revealEnd
        ) {
            throw new Error(
                "Reveal period ended before the transaction was sent."
            );
        }

        /*
         * SUBMIT THE REVEAL
         */

        console.log(
            "Submitting reveal for",
            ethers.utils.formatEther(
                bidAmount
            ),
            "ETH"
        );

        const transaction =
            await contract.revealBid(
                bidAmount,
                salt,
                {
                    value: bidAmount,

                    /*
                     * Providing a gas limit avoids relying on a
                     * pre-transaction gas estimate before the
                     * next Remix VM block is created.
                     */
                    gasLimit: 300000
                }
            );

        console.log(
            "Transaction submitted:",
            transaction.hash
        );

        const receipt =
            await transaction.wait();

        console.log(
            "Reveal confirmed in block:",
            receipt.blockNumber
        );

        const highestBidder =
            await contract.highestBidder();

        const highestBid =
            await contract.highestBid();

        console.log(
            "Highest bidder:",
            highestBidder
        );

        console.log(
            "Highest bid:",
            ethers.utils.formatEther(
                highestBid
            ),
            "ETH"
        );
    } catch (error) {
        console.error(
            "Queued reveal failed:",
            error.message || error
        );
    }
})();