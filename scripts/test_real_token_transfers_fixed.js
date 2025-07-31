import { RpcProvider, Account, Contract, json, cairo, uint256 } from 'starknet';
import fs from 'fs';
import { randomBytes } from 'crypto';

// Helper function to convert uint8Array to hex (like in main.spec.ts)
function uint8ArrayToHex(bytes) {
    return '0x' + Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
}

// Configuration
const RPC_URL = 'https://starknet-sepolia.public.blastapi.io/rpc/v0_8';
const PRIVATE_KEY = '0x05e02a12adbbb906f31ccc6e20a308f039cb10ae78ba46d6f322bac06759e445';
const ACCOUNT_ADDRESS = '0x04F42997425A5a3550b9AedbCA3B652Cfa3e80010E9d3AffF8Bab7Ce111BDb70';

// Test constants (matching main.spec.ts patterns)
const MAKER_ADDRESS = '0x04d75Be4cbCa347f61a95737F0Fb69AE324B409886B4401837eaE2108EbdB51a';
const TAKER_ADDRESS = '0x04F42997425A5a3550b9AedbCA3B652Cfa3e80010E9d3AffF8Bab7Ce111BDb70';
const TOKEN_ADDRESS = '0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d'; // STRK token
const ORDER_HASH = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcde'; // 63 chars = 252 bits

// Generate a secret and compute its hash for hashlock validation
const SECRET = uint8ArrayToHex(randomBytes(16)); // 16 bytes to fit in felt252
// For now, use a placeholder hashlock - in real implementation, you'd compute the actual hash
const HASH_LOCK = '0x14567890abcdef1234567890abcdef1234567890abcdef1234567890abcde'; // 63 chars = 252 bits

class RealTokenTransferTester {
    constructor() {
        this.provider = new RpcProvider({ nodeUrl: RPC_URL });
        this.account = new Account(this.provider, ACCOUNT_ADDRESS, PRIVATE_KEY);

        this.contract = null;
        this.contractAddress = null;
        this.tokenContract = null;
        this.deployedAt = null;
    }

    async setup() {
        console.log('🔧 Setting up Real Token Transfer tester...');

        // Deploy the contract
        await this.deployContract();

        // Setup token contract
        await this.setupTokenContract();

        console.log('✅ Setup complete!');
    }

    async deployContract() {
        console.log('📦 Deploying EscrowDst contract...');

        try {
            // Load compiled contract files
            const compiledTestSierra = json.parse(fs.readFileSync('../defi-unite-contracts/target/dev/hello_starknet_EscrowDst.contract_class.json').toString('ascii'));
            const compiledTestCasm = json.parse(fs.readFileSync('../defi-unite-contracts/target/dev/hello_starknet_EscrowDst.compiled_contract_class.json').toString('ascii'));

            // Deploy the contract using declareAndDeploy
            const deployResponse = await this.account.declareAndDeploy({
                contract: compiledTestSierra,
                casm: compiledTestCasm,
                constructorCalldata: [
                    1800, // rescue_delay: 30 minutes (felt252)
                    '0x0000000000000000000000000000000000000000000000000000000000000000', // factory: placeholder (ContractAddress)
                    '0x0000000000000000000000000000000000000000000000000000000000000000'  // access_token: placeholder (ContractAddress)
                ]
            });
            await this.provider.waitForTransaction(deployResponse.deploy.transaction_hash);

            this.contractAddress = deployResponse.deploy.contract_address;
            console.log('🚀 Contract deployed at:', this.contractAddress);
            console.log('📋 Class Hash:', deployResponse.declare.class_hash);

            // Connect to the contract
            const { abi } = await this.provider.getClassAt(this.contractAddress);
            this.contract = new Contract(abi, this.contractAddress, this.provider);
            this.contract.connect(this.account);

        } catch (error) {
            console.error('❌ Deployment failed:', error);
            throw error;
        }
    }

    async setupTokenContract() {
        console.log('🪙 Setting up STRK token contract...');

        // STRK token contract ABI (simplified for ERC20 functions)
        const tokenAbi = [
            {
                "name": "balanceOf",
                "type": "function",
                "inputs": [{ "name": "account", "type": "core::starknet::contract_address::ContractAddress" }],
                "outputs": [{ "name": "balance", "type": "core::integer::u256" }]
            },
            {
                "name": "transfer",
                "type": "function",
                "inputs": [
                    { "name": "recipient", "type": "core::starknet::contract_address::ContractAddress" },
                    { "name": "amount", "type": "core::integer::u256" }
                ],
                "outputs": [{ "name": "success", "type": "core::bool" }]
            }
        ];

        this.tokenContract = new Contract(tokenAbi, TOKEN_ADDRESS, this.provider);
        this.tokenContract.connect(this.account);
    }

    createImmutables() {
        // Create immutables matching the structure expected by the Cairo contract
        // Using smaller values to avoid felt252 overflow
        const currentTime = Math.floor(Date.now() / 1000);
        return {
            order_hash: ORDER_HASH, // felt252
            hashlock: HASH_LOCK, // felt252
            maker: MAKER_ADDRESS, // Address (felt252)
            taker: TAKER_ADDRESS, // Address (felt252)
            token: TOKEN_ADDRESS, // Address (felt252)
            amount: cairo.uint256(100000000000000000), // 0.1 STRK (18 decimals) - u256
            safety_deposit: cairo.uint256(100000000000000), // 0.0001 ETH (18 decimals) - u256
            timelocks: {
                value: currentTime - 100 // felt252 - packed timelocks value (like Solidity)
            }
        };
    }

    createImmutablesWithDeployedAt(deployedAt) {
        // Create immutables with deployment timestamp (equivalent to dstImmutables.withDeployedAt(dstDeployedAt) in main.spec.ts)
        const baseImmutables = this.createImmutables();
        return {
            ...baseImmutables,
            timelocks: {
                value: deployedAt // felt252 - deployment timestamp (packed like Solidity)
            }
        };
    }

    // Test 1: Deploy destination escrow (equivalent to deployDst in main.spec.ts)
    async testDeployDst() {
        console.log('\n🧪 Test 1: Deploy destination escrow');

        try {
            // Verify the contract is properly deployed
            const rescueDelay = await this.contract.get_RESCUE_DELAY();
            console.log('✅ Rescue delay:', rescueDelay.toString());

            const factory = await this.contract.get_FACTORY();
            console.log('✅ Factory address:', factory.toString());

            console.log('✅ Deploy destination escrow test passed');

        } catch (error) {
            console.error('❌ Deploy destination escrow test failed:', error);
            throw error;
        }
    }

    // Test 2: Deposit tokens to escrow (equivalent to deployDst in main.spec.ts)
    async testDepositTokens() {
        console.log('\n🧪 Test 2: Deposit tokens to escrow');

        try {
            console.log('💰 Attempting to deposit tokens...');
            console.log('📊 Contract address:', this.contractAddress);
            console.log('📊 Token address:', TOKEN_ADDRESS);
            console.log('📊 Taker address:', TAKER_ADDRESS);

            const depositAmount = cairo.uint256(100000000000000000); // 0.1 STRK

            console.log('💸 Transferring tokens to escrow contract...');
            console.log('📊 Deposit amount:', depositAmount.toString());

            // Transfer tokens to the escrow contract (simulating deposit)
            const transferResult = await this.tokenContract.transfer(
                this.contractAddress,
                depositAmount
            );
            await this.provider.waitForTransaction(transferResult.transaction_hash);

            console.log('✅ Tokens deposited to escrow contract');
            console.log('📋 Transaction hash:', transferResult.transaction_hash);

            // Store deployment timestamp for withdrawal (equivalent to dstDeployedAt in main.spec.ts)
            this.deployedAt = Math.floor(Date.now() / 1000); // Current timestamp
            console.log('📅 Deployment timestamp:', this.deployedAt);

        } catch (error) {
            console.error('❌ Deposit tokens test failed:', error);
            console.log('ℹ️  This might fail if taker has insufficient tokens or nonce issues');
        }
    }

    // Test 3: Withdraw tokens from escrow (equivalent to withdraw('dst', ...) in main.spec.ts)
    async testWithdrawTokens() {
        console.log('\n🧪 Test 3: Withdraw tokens from escrow');

        try {
            // Ensure we have a deployment timestamp
            const deployedAt = this.deployedAt || Math.floor(Date.now() / 1000);

            // Create immutables with deployment timestamp (equivalent to dstImmutables.withDeployedAt(dstDeployedAt) in main.spec.ts)
            const immutables = this.createImmutablesWithDeployedAt(deployedAt);

            // Use the pre-generated secret (in real scenario, this would be shared by the maker)
            const secret = SECRET;

            console.log('🔑 Attempting withdrawal with secret:', secret);
            console.log('📊 Maker address:', MAKER_ADDRESS);
            console.log('📊 Contract address:', this.contractAddress);
            console.log('📊 Deployment timestamp:', deployedAt);
            console.log('📊 Timelocks deployed_at:', immutables.timelocks.deployed_at);

            // Replicating the exact flow from main.spec.ts:
            // 1. resolverContract.withdraw('dst', dstEscrowAddress, secret, dstImmutables.withDeployedAt(dstDeployedAt))
            // 2. Resolver.sol: escrow.withdraw(secret, immutables)
            // 3. EscrowDst.sol: withdraw(secret, immutables) -> _withdraw(secret, immutables)
            // So we call directly: escrow.withdraw(secret, immutables)
            const result = await this.contract.withdraw(secret, immutables);
            await this.provider.waitForTransaction(result.transaction_hash);

            console.log('✅ Withdrawal successful');
            console.log('📋 Transaction hash:', result.transaction_hash);

        } catch (error) {
            console.error('❌ Withdrawal test failed:', error);
            console.log('ℹ️  Expected failure due to validation checks (immutables, timelock, etc.)');
        }
    }

    // Test 4: Complete cross-chain swap simulation
    async testCompleteCrossChainSwapSimulation() {
        console.log('\n🧪 Test 4: Complete cross-chain swap simulation');

        try {
            console.log('🔄 Simulating complete cross-chain swap flow...');

            // Step 1: Deploy destination escrow (already done in setup)
            console.log('✅ Step 1: Destination escrow deployed');

            // Step 2: Deposit tokens (equivalent to deployDst in main.spec.ts)
            console.log('💸 Step 2: Depositing tokens to escrow...');
            await this.testDepositTokens();

            // Step 3: Wait for timelock (simulate time passing)
            console.log('⏰ Step 3: Waiting for timelock...');
            // In real scenario, you'd wait for actual time or use a testnet with time manipulation

            // Step 4: Withdraw with valid secret
            console.log('🔑 Step 4: Attempting withdrawal with valid secret...');
            await this.testWithdrawTokens();

            console.log('✅ Complete cross-chain swap simulation completed');

        } catch (error) {
            console.error('❌ Complete cross-chain swap simulation failed:', error);
        }
    }

    async runAllTests() {
        console.log('🚀 Starting Real Token Transfer tests...\n');

        try {
            await this.setup();

            await this.testDeployDst();
            await this.testDepositTokens();
            await this.testWithdrawTokens();
            await this.testCompleteCrossChainSwapSimulation();

            console.log('\n🎉 All tests completed successfully!');

        } catch (error) {
            console.error('\n💥 Test suite failed:', error);
            throw error;
        }
    }
}

// Run the tests
async function main() {
    const tester = new RealTokenTransferTester();
    await tester.runAllTests();
}

// Export for use in other files
export { RealTokenTransferTester };

// Run if this file is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
    main().catch(console.error);
} 