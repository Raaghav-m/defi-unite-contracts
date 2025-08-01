// Base Sepolia Configuration for Fusion+ Cross-Chain Swaps
// Similar to config.ts in main.spec.ts but adapted for Base Sepolia

const baseSepoliaConfig = {
    chain: {
        source: {
            chainId: 1, // Ethereum mainnet (supported by SDK)
            url: 'https://base-sepolia.g.alchemy.com/v2/dLPhzR_JWxIrgljDBn98t_C2A5Bow1bh',
            createFork: false, // We're using real Base Sepolia, not a fork
            limitOrderProtocol: '0x111111125421ca6dc452d289314280a0f8842a65', // 1inch LOP
            wrappedNative: '0x4200000000000000000000000000000000000006', // WETH on Base Sepolia
            ownerPrivateKey: '0x33d49c71f0dbadf7ecf1f492bfb1a678025182d70cf82b50c06ba157b8a02700',
            tokens: {
                USDC: {
                    address: '0x036CbD53842c5426634e7929541eC2318f3dCF7e', // Base Sepolia USDC
                    donor: '0x5C57695B06D57249842dBb0018ED9293C182BaEa' // Your address as donor
                }
            }
        },
        destination: {
            chainId: 137, // Polygon (supported by SDK)
            url: 'https://alpha-sepolia.starknet.io',
            createFork: false,
            limitOrderProtocol: '0x111111125421ca6dc452d289314280a0f8842a65',
            wrappedNative: '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7', // WETH on Starknet
            ownerPrivateKey: '0x33d49c71f0dbadf7ecf1f492bfb1a678025182d70cf82b50c06ba157b8a02700',
            tokens: {
                USDC: {
                    address: '0x1234567890123456789012345678901234567890', // USDC on Starknet (using Ethereum format for SDK compatibility)
                    donor: '0x5C57695B06D57249842dBb0018ED9293C182BaEa'
                }
            }
        }
    }
};

// Test constants (from main.spec.ts)
const TEST_CONSTANTS = {
    userPk: '0x33d49c71f0dbadf7ecf1f492bfb1a678025182d70cf82b50c06ba157b8a02700',
    resolverPk: '0x33d49c71f0dbadf7ecf1f492bfb1a678025182d70cf82b50c06ba157b8a02700',
    makerAddress: '0x5C57695B06D57249842dBb0018ED9293C182BaEa',
    takerAddress: '0x04F42997425A5a3550b9AedbCA3B652Cfa3e80010E9d3AffF8Bab7Ce111BDb70'
};

module.exports = { baseSepoliaConfig, TEST_CONSTANTS }; 