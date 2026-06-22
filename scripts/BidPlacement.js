const { ethers } = require("ethers");

(async () => {
    try {
        // Paste the deployed SignedSealedBidAuction address.
        const contractAddress =
            "PASTE CONTRACT ADDRESS";

        // Paste one account from Remix VM.
        const bidderAddress =
            "PASTE ACCOUNT ADDRESS";

        const abi = [
            "function makeCommitment(address bidder, uint256 bidAmount, bytes32 salt) view returns (bytes32)",
            "function getCommitAuthorizationHash(address bidder, bytes32 commitment, uint256 nonce, uint256 deadline) view returns (bytes32)",
            "function nonces(address bidder) view returns (uint256)",
            "function commitBid(address bidder, bytes32 commitment, uint256 nonce, uint256 deadline, bytes signature)"
        ];

        const provider =
            new ethers.providers.Web3Provider(
                web3Provider
            );

        const signer =
            provider.getSigner(bidderAddress);

        const contract =
            new ethers.Contract(
                contractAddress,
                abi,
                signer
            );

        // Test bid: 1 ETH.
        const bidAmount =
            ethers.utils.parseEther("2");

        const salt =
            "0x8f3a6d9c41e7b2f05c8d13a964be27f1d5c7048a9e6b32f0c147da85b39e62ac";

        const nonce =
            await contract.nonces(
                bidderAddress
            );

        const commitment =
            await contract.makeCommitment(
                bidderAddress,
                bidAmount,
                salt
            );

        // Use the Remix VM blockchain timestamp.
        const latestBlock =
            await provider.getBlock("latest");

        const deadline =
            latestBlock.timestamp + 300;

        const authorizationHash =
            await contract.getCommitAuthorizationHash(
                bidderAddress,
                commitment,
                nonce,
                deadline
            );

        const signature =
            await signer.signMessage(
                ethers.utils.arrayify(
                    authorizationHash
                )
            );

        console.log("Bidder:", bidderAddress);
        console.log(
            "Bid amount:",
            bidAmount.toString()
        );
        console.log("Salt:", salt);
        console.log("Commitment:", commitment);
        console.log(
            "Nonce:",
            nonce.toString()
        );
        console.log("Deadline:", deadline);
        console.log("Signature:", signature);

        const recovered =
            ethers.utils.verifyMessage(
                ethers.utils.arrayify(
                    authorizationHash
                ),
                signature
            );

        console.log(
            "Recovered signer:",
            recovered
        );

        if (
            recovered.toLowerCase() !==
            bidderAddress.toLowerCase()
        ) {
            throw new Error(
                "Signature does not match bidder"
            );
        }

        const transaction =
            await contract.commitBid(
                bidderAddress,
                commitment,
                nonce,
                deadline,
                signature
            );

        console.log(
            "Commit transaction:",
            transaction.hash
        );

        await transaction.wait();

        console.log(
            "Commitment submitted successfully"
        );
    } catch (error) {
        console.error(
            "Error:",
            error.message || error
        );
    }
})();