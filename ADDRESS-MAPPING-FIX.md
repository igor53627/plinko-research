# Address Mapping Fix

## Problem

When testing privacy mode with different Ethereum addresses, you observed:
- `0x00000000219ab540356cBB839Cbe05303d7705Fa` (Eth2 Deposit Contract) → shows **0 ETH**
- `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` (WETH Contract) → shows **0 ETH**
- `0x1000000000000000000000000000000000000042` → shows **18.0179 ETH** ✅

## Root Cause

The test database only contains addresses in the range `0x1000000000000000000000000000000000000000` upwards. The database generator (`services/db-generator/main.go`) creates sequential addresses starting from that base address.

However, the JavaScript PIR client was using a **hash-based address-to-index mapping** instead of the actual `address-mapping.bin` file:

```javascript
// OLD (BROKEN) CODE
addressToIndex(address) {
  const addrHex = address.toLowerCase().replace('0x', '');
  
  // Simple hash: sum of bytes mod dbSize
  let hash = 0;
  for (let i = 0; i < addrHex.length; i += 2) {
    hash += parseInt(addrHex.substr(i, 2), 16);
  }
  
  return hash % (this.metadata?.dbSize || 8388608);
}
```

This caused:
1. **Incorrect lookups** - hash collisions mapped addresses to wrong indices
2. **False zeros** - Eth2 and WETH addresses hashed to indices containing 0 balance
3. **Accidental success** - The test address `0x10...042` happened to hash close to its actual index

## Solution

The fix downloads and uses `address-mapping.bin` for accurate address-to-index lookups:

```javascript
// NEW (FIXED) CODE
async downloadAddressMapping() {
  const response = await fetch(`${this.cdnUrl}/address-mapping.bin`);
  const mappingData = await response.arrayBuffer();
  
  this.addressMapping = new Map();
  
  const entrySize = 24; // 20 bytes address + 4 bytes index
  const numEntries = mappingData.byteLength / entrySize;
  
  for (let i = 0; i < numEntries; i++) {
    const offset = i * entrySize;
    const addressBytes = new Uint8Array(mappingData, offset, 20);
    const addressHex = '0x' + Array.from(addressBytes)
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
    const index = view.getUint32(offset + 20, true);
    
    this.addressMapping.set(addressHex.toLowerCase(), index);
  }
}

addressToIndex(address) {
  const normalizedAddress = address.toLowerCase();
  
  if (this.addressMapping && this.addressMapping.has(normalizedAddress)) {
    return this.addressMapping.get(normalizedAddress);
  }
  
  throw new Error(`Address ${address} not found in database`);
}
```

## Changes Made

1. **`services/rabby-wallet/src/clients/plinko-pir-client.js`**
   - Added `downloadAddressMapping()` method
   - Modified `downloadHint()` to also download address mapping
   - Replaced hash-based `addressToIndex()` with Map lookup
   - Added clear error message for addresses not in database

2. **Created test script**: `test-address-mapping.js`
   - Verifies the address mapping works correctly
   - Tests both in-database and out-of-database addresses

## Testing

Run the test script to verify the fix:

```bash
node test-address-mapping.js
```

Expected output:
```
✅ Loaded 8388608 address mappings

Testing addresses:
────────────────────────────────────────────────────────────────────────────────
✅ Eth2 Deposit Contract
   Address: 0x00000000219ab540356cBB839Cbe05303d7705Fa
   Status: Not in database
   Expected: Not found

✅ WETH Contract
   Address: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
   Status: Not in database
   Expected: Not found

✅ DB Address #66
   Address: 0x1000000000000000000000000000000000000042
   Index: 66
   Expected: Found
```

## Using Privacy Mode

When testing privacy mode, **only use addresses that exist in the database**:

### Addresses in the database:
- Start: `0x1000000000000000000000000000000000000000`
- End: `0x100000000000000000000000000000000080001f` (with default 8M addresses)

### Example test addresses with balances:
```bash
# First address (index 0)
0x1000000000000000000000000000000000000000

# Address at index 66
0x1000000000000000000000000000000000000042

# Address at index 100
0x1000000000000000000000000000000000000064
```

### What happens with addresses NOT in the database:

The client will now throw a clear error:
```
Error: Address 0x00000000219ab540356cBB839Cbe05303d7705Fa not found in database.
Only addresses in range 0x1000...0000 to 0x1000...80001f are indexed.
```

## Database Structure

The Plinko PIR test system uses:

1. **`database.bin`** - 8 bytes per address (uint64 balance in wei)
2. **`address-mapping.bin`** - 24 bytes per entry:
   - 20 bytes: Ethereum address
   - 4 bytes: Database index (little-endian uint32)
3. **`hint.bin`** - Copy of database.bin with metadata header

All addresses are sorted lexicographically for deterministic ordering.

## Why This Matters for Privacy

The hash-based approach was never intended for production use (as noted in the code comments). Using the correct address-mapping ensures:

1. **Correct balance queries** - You get the actual balance for the queried address
2. **Proper PIR operation** - The PIR set expansion works on the correct database index
3. **Delta synchronization** - Hint updates apply to the correct entries

## Next Steps

To test privacy mode with **real Ethereum addresses**, you would need to:

1. Generate a database from actual Ethereum state (using a full node)
2. Create an `address-mapping.bin` with real addresses
3. Deploy the PIR system with that data

For the PoC, stick to addresses in the `0x1000...` range that are actually in the test database.
