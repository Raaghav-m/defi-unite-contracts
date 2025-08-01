import { ethers } from 'ethers';
import fs from 'fs';
import path from 'path';

// Configuration for EVM source chain (Base Sepolia)
const RPC_URL = 'https://base-sepolia.g.alchemy.com/v2/dLPhzR_JWxIrgljDBn98t_C2A5Bow1bh';
const PRIVATE_KEY = '0x33d49c71f0dbadf7ecf1f492bfb1a678025182d70cf82b50c06ba157b8a02700';

// Test constants
const MAKER_ADDRESS = '0x5C57695B06D57249842dBb0018ED9293C182BaEa';
const TAKER_ADDRESS = '0x04F42997425A5a3550b9AedbCA3B652Cfa3e80010E9d3AffF8Bab7Ce111BDb70';
const USDC_ADDRESS = '0x036CbD53842c5426634e7929541eC2318f3dCF7e'; // Base Sepolia USDC

// Contract deployment parameters (based on main.spec.ts)
const LIMIT_ORDER_PROTOCOL = '0x111111125421ca6dc452d289314280a0f8842a65'; // 1inch Limit Order Protocol
const WRAPPED_NATIVE = '0x4200000000000000000000000000000000000006'; // WETH on Base Sepolia
const RESOLVER_PRIVATE_KEY = '0x33d49c71f0dbadf7ecf1f492bfb1a678025182d70cf82b50c06ba157b8a02700'; // From main.spec.ts

class EVMContractDeployer {
    constructor() {
        this.provider = new ethers.JsonRpcProvider(RPC_URL);
        this.deployer = new ethers.Wallet(PRIVATE_KEY, this.provider);

        this.escrowFactory = null;
        this.resolver = null;
        this.limitOrderProtocol = null;
    }

    loadContractArtifact(contractPath) {
        try {
            const fullPath = path.resolve(contractPath);
            console.log(`📁 Loading contract from: ${fullPath}`);

            if (!fs.existsSync(fullPath)) {
                throw new Error(`Contract file not found: ${fullPath}`);
            }

            const contractJson = JSON.parse(fs.readFileSync(fullPath, 'utf8'));

            if (!contractJson.abi) {
                throw new Error(`No ABI found in contract file: ${fullPath}`);
            }

            if (!contractJson.bytecode) {
                throw new Error(`No bytecode found in contract file: ${fullPath}`);
            }

            console.log(`✅ Contract loaded successfully: ${path.basename(contractPath)}`);
            return contractJson;

        } catch (error) {
            console.error(`❌ Failed to load contract from ${contractPath}:`, error.message);
            throw error;
        }
    }

    async deployContracts() {
        console.log('🔧 Deploying EVM contracts...');

        try {
            // Load compiled contract artifacts
            const factoryArtifact = this.loadContractArtifact('../../cross-chain-resolver-example/dist/contracts/TestEscrowFactory.sol/TestEscrowFactory.json');
            const resolverArtifact = this.loadContractArtifact('../../cross-chain-resolver-example/dist/contracts/Resolver.sol/Resolver.json');

            console.log('📦 Deploying EscrowFactory...');

            // EscrowFactory constructor parameters (from main.spec.ts)
            const factoryConstructorArgs = [
                LIMIT_ORDER_PROTOCOL, // limitOrderProtocol
                WRAPPED_NATIVE, // feeToken (wrapped native)
                '0x0000000000000000000000000000000000000000', // accessToken (zero address)
                await this.deployer.getAddress(), // owner
                60 * 30, // src rescue delay (30 minutes)
                60 * 30 // dst rescue delay (30 minutes)
            ];

            // Deploy EscrowFactory
            const EscrowFactory = new ethers.ContractFactory(
                factoryArtifact.abi,
                factoryArtifact.bytecode,
                this.deployer
            );
            this.escrowFactory = await EscrowFactory.deploy(...factoryConstructorArgs);
            await this.escrowFactory.waitForDeployment();

            const factoryAddress = await this.escrowFactory.getAddress();
            console.log('✅ EscrowFactory deployed at:', factoryAddress);

            console.log('📦 Deploying Resolver...');

            // Resolver constructor parameters (from main.spec.ts)
            const resolverPrivateKey = RESOLVER_PRIVATE_KEY;
            const resolverOwnerAddress = ethers.computeAddress(resolverPrivateKey);
            const resolverConstructorArgs = [
                factoryAddress, // escrowFactory
                LIMIT_ORDER_PROTOCOL, // limitOrderProtocol
                resolverOwnerAddress // resolver as owner of contract
            ];

            // Deploy Resolver
            const Resolver = new ethers.ContractFactory(
                resolverArtifact.abi,
                resolverArtifact.bytecode,
                this.deployer
            );
            this.resolver = await Resolver.deploy(...resolverConstructorArgs);
            await this.resolver.waitForDeployment();

            const resolverAddress = await this.resolver.getAddress();
            console.log('✅ Resolver deployed at:', resolverAddress);

            // Get LimitOrderProtocol address
            this.limitOrderProtocol = LIMIT_ORDER_PROTOCOL;

            console.log('\n🎉 EVM Contract Deployment Complete!');
            console.log('📊 Deployment Summary:');
            console.log('  - EscrowFactory:', factoryAddress);
            console.log('  - Resolver:', resolverAddress);
            console.log('  - LimitOrderProtocol:', this.limitOrderProtocol);
            console.log('  - Deployer:', await this.deployer.getAddress());
            console.log('  - Resolver Owner:', resolverOwnerAddress);

            // Save deployment addresses to file
            const deploymentInfo = {
                escrowFactory: factoryAddress,
                resolver: resolverAddress,
                limitOrderProtocol: this.limitOrderProtocol,
                deployer: await this.deployer.getAddress(),
                resolverOwner: resolverOwnerAddress,
                network: 'base-sepolia',
                timestamp: new Date().toISOString()
            };

            fs.writeFileSync('evm_deployment.json', JSON.stringify(deploymentInfo, null, 2));
            console.log('💾 Deployment info saved to evm_deployment.json');

            return deploymentInfo;

        } catch (error) {
            console.error('❌ Contract deployment failed:', error);
            throw error;
        }
    }

    async setupTokenApprovals() {
        console.log('\n🪙 Setting up token approvals...');

        try {
            // USDC token contract
            const usdcAbi = [
                "function approve(address spender, uint256 amount) external returns (bool)",
                "function balanceOf(address account) external view returns (uint256)",
                "function transfer(address to, uint256 amount) external returns (bool)"
            ];
            const usdcContract = new ethers.Contract(USDC_ADDRESS, usdcAbi, this.deployer);

            // Check USDC balance
            const balance = await usdcContract.balanceOf(await this.deployer.getAddress());
            console.log('💰 USDC Balance:', ethers.formatUnits(balance, 6));

            // Approve LimitOrderProtocol to spend USDC
            const approvalTx = await usdcContract.approve(this.limitOrderProtocol, ethers.MaxUint256);
            await approvalTx.wait();
            console.log('✅ USDC approval for LimitOrderProtocol completed');

            // Transfer some USDC to resolver for testing (only if we have enough balance)
            const transferAmount = ethers.parseUnits('10', 6); // Reduced from 1000 to 10
            if (balance >= transferAmount) {
                const transferTx = await usdcContract.transfer(await this.resolver.getAddress(), transferAmount);
                await transferTx.wait();
                console.log('✅ USDC transferred to resolver:', ethers.formatUnits(transferAmount, 6));
            } else {
                console.log('⚠️  Insufficient USDC balance for transfer to resolver. Skipping transfer.');
                console.log('   Available:', ethers.formatUnits(balance, 6), 'USDC');
                console.log('   Required:', ethers.formatUnits(transferAmount, 6), 'USDC');
            }

        } catch (error) {
            console.error('❌ Token approval setup failed:', error);
            console.log('⚠️  Continuing without token setup...');
            // Don't throw error, just log it and continue
        }
    }

    async runDeployment() {
        console.log('🚀 Starting EVM Contract Deployment...\n');

        try {
            // Deploy contracts
            const deploymentInfo = await this.deployContracts();

            // Setup token approvals
            await this.setupTokenApprovals();

            console.log('\n✅ EVM Contract Deployment completed successfully!');
            return deploymentInfo;

        } catch (error) {
            console.error('\n💥 EVM Contract Deployment failed:', error);
            throw error;
        }
    }
}

// Main execution
async function main() {
    const deployer = new EVMContractDeployer();
    await deployer.runDeployment();
}

// Export for use in other files
export { EVMContractDeployer };

// Run if this file is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
    main().catch(console.error);
} 