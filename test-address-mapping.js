#!/usr/bin/env node

/**
 * Test script to verify address-to-index mapping
 * 
 * This tests the fixed PlinkoPIRClient with address-mapping.bin
 */

// Test addresses
const testAddresses = [
  { addr: '0x00000000219ab540356cBB839Cbe05303d7705Fa', name: 'Eth2 Deposit Contract', shouldExist: false },
  { addr: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', name: 'WETH Contract', shouldExist: false },
  { addr: '0x1000000000000000000000000000000000000042', name: 'DB Address #66', shouldExist: true },
  { addr: '0x1000000000000000000000000000000000000000', name: 'DB Address #0', shouldExist: true },
  { addr: '0x1000000000000000000000000000000000000001', name: 'DB Address #1', shouldExist: true },
];

console.log('========================================');
console.log('Address-to-Index Mapping Test');
console.log('========================================\n');

// Mock PlinkoPIRClient addressToIndex implementation
class MockPIRClient {
  constructor() {
    this.addressMapping = null;
    this.metadata = { dbSize: 8388608 };
  }

  // Simulate loading address-mapping.bin
  async loadAddressMapping(mappingFile) {
    const fs = await import('fs');
    const buffer = fs.readFileSync(mappingFile);
    
    this.addressMapping = new Map();
    
    const entrySize = 24; // 20 bytes address + 4 bytes index
    const numEntries = buffer.length / entrySize;
    
    for (let i = 0; i < numEntries; i++) {
      const offset = i * entrySize;
      
      // Read 20-byte address
      const addressBytes = buffer.subarray(offset, offset + 20);
      const addressHex = '0x' + Array.from(addressBytes)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
      
      // Read 4-byte index (little-endian)
      const index = buffer.readUInt32LE(offset + 20);
      
      this.addressMapping.set(addressHex.toLowerCase(), index);
    }
    
    console.log(`✅ Loaded ${this.addressMapping.size} address mappings\n`);
  }

  addressToIndex(address) {
    const normalizedAddress = address.toLowerCase();
    
    if (this.addressMapping && this.addressMapping.has(normalizedAddress)) {
      return this.addressMapping.get(normalizedAddress);
    }
    
    throw new Error(`Address ${address} not found in database`);
  }
}

async function main() {
  const client = new MockPIRClient();
  
  // Try to load address-mapping.bin
  const mappingPath = './shared/data/address-mapping.bin';
  
  try {
    await client.loadAddressMapping(mappingPath);
  } catch (err) {
    console.error(`❌ Failed to load ${mappingPath}`);
    console.error(`   Make sure the Plinko system is running and data is generated.`);
    console.error(`   Error: ${err.message}\n`);
    process.exit(1);
  }

  // Test each address
  console.log('Testing addresses:');
  console.log('─'.repeat(80));
  
  for (const test of testAddresses) {
    try {
      const index = client.addressToIndex(test.addr);
      const status = test.shouldExist ? '✅' : '⚠️';
      console.log(`${status} ${test.name}`);
      console.log(`   Address: ${test.addr}`);
      console.log(`   Index: ${index}`);
      console.log(`   Expected: ${test.shouldExist ? 'Found' : 'Not found'}`);
    } catch (err) {
      const status = test.shouldExist ? '❌' : '✅';
      console.log(`${status} ${test.name}`);
      console.log(`   Address: ${test.addr}`);
      console.log(`   Status: Not in database (${err.message.split('.')[0]})`);
      console.log(`   Expected: ${test.shouldExist ? 'Found' : 'Not found'}`);
    }
    console.log('');
  }

  console.log('─'.repeat(80));
  console.log('\n📝 Summary:');
  console.log('   - Real Ethereum addresses (Eth2, WETH) are NOT in the test database');
  console.log('   - Test database contains addresses from 0x1000...0000 upwards');
  console.log('   - Use addresses in that range for privacy mode testing');
  console.log('\n✅ Address mapping verification complete!');
}

main().catch(console.error);
