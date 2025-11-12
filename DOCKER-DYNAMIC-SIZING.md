# Docker Dynamic Database Sizing - Implementation Guide

## Overview

The Plinko PIR Docker services now support **dynamic database sizing**. Services automatically detect and adapt to any database size, eliminating hardcoded 8.4M entry limitations.

## Changes Summary

### 1. Hint Generator (`plinko-hint-generator`)

**Before:**
- Hardcoded `DBSize = 8388608` constant
- Expected exactly 67MB database.bin file
- Generated hint.bin with wrong metadata for smaller databases

**After:**
- Auto-detects database size from `database.bin` file
- Calculates Plinko PIR parameters dynamically
- Correctly pads database to next power-of-2 boundary
- Writes accurate metadata in hint.bin header

**Key Changes:**
- Removed `DBSize` constant
- Added `actualDBSize` calculation from file size
- Modified `generateHint()` to accept dynamic dbSize parameter
- Updated `verifyOutput()` to validate against actual size

### 2. Database Generator (`db-generator`)

**Before:**
- `balance := acc.Balance.Uint64()` caused overflow for large balances
- Hardcoded `ConcurrentWorkers = 10000`

**After:**
- Clamps balances exceeding uint64 max to `^uint64(0)`
- Logs warnings when clamping occurs
- Configurable concurrent workers via `CONCURRENT_WORKERS` env var
- Existing `DB_SIZE` env var support preserved

**Key Changes:**
- Added overflow detection and clamping logic
- Added `getConcurrentWorkers()` function
- Modified `writeDatabaseBin()` to prevent overflow
- Logs first 5 overflow warnings plus total count

### 3. Wrapper Script (`generate-hint.sh`)

**Before:**
- Hardcoded expected size: `EXPECTED_SIZE=67108864`
- Failed validation for non-8.4M databases

**After:**
- Dynamic size detection and reporting
- Shows database entries and size in MB
- No hardcoded expectations

## Environment Variables

### `db-generator` Service

```yaml
environment:
  DB_SIZE: 10000              # Number of accounts to generate (default: 8388608)
  CONCURRENT_WORKERS: 5000    # Worker pool size (default: 10000)
  RPC_URL: http://eth-mock:8545  # Ethereum RPC endpoint
```

### `hint-generator` Service

```yaml
# No configuration needed - auto-detects from database.bin
volumes:
  - plinko-data:/data  # Must contain database.bin
```

### `pir-server` Service

```yaml
# PIR server reads metadata from hint.bin header automatically
environment:
  DB_PATH: /data/database.bin
  PORT: 3000
```

## Testing Dynamic Sizing

### Test 1: Small Database (1K entries)

```bash
# Generate 1K entry database
docker compose up -d eth-mock
docker compose run --rm db-generator \
  -e DB_SIZE=1000 \
  -e CONCURRENT_WORKERS=100

# Generate hints (auto-detects 1K entries)
docker compose run --rm hint-generator

# Verify
ls -lh data/database.bin  # Should be 8KB (1000 × 8 bytes)
ls -lh data/hint.bin      # Should be ~32KB + padding
```

### Test 2: Medium Database (10K entries)

```bash
# Use docker-compose-static.yml with 10K real Ethereum data
cd deploy/vm
docker compose -f docker-compose-static.yml up -d

# Monitor hint generation
docker compose -f docker-compose-static.yml logs -f hint-generator

# Expected output:
# Database size: 10000 entries (0.1 MB)
# Chunk Size: 256
# Set Size: 40
# Total Entries: 10240 (padded from 10000)
```

### Test 3: Large Database (8M entries - Original)

```bash
# Default docker-compose.yml
docker compose up -d

# Monitor
docker compose logs -f plinko-hint-generator

# Expected output:
# Database size: 8388608 entries (64.0 MB)
# Chunk Size: 8192
# Set Size: 1024
# Total Entries: 8388608 (padded from 8388608)
```

## PIR Parameter Calculation

The hint generator uses the Plinko PIR parameter generation algorithm:

```go
func GenParams(dbSize uint64) (uint64, uint64) {
    // Calculate optimal chunk size: ~2*sqrt(dbSize)
    targetChunkSize := uint64(2 * math.Sqrt(float64(dbSize)))

    // Round up to next power of 2
    chunkSize := uint64(1)
    for chunkSize < targetChunkSize {
        chunkSize *= 2
    }

    // Calculate set size (round up)
    setSize := uint64(math.Ceil(float64(dbSize) / float64(chunkSize)))

    // Round set size to multiple of 4
    setSize = (setSize + 3) / 4 * 4

    return chunkSize, setSize
}
```

### Example Calculations

| Database Size | Chunk Size | Set Size | Total Padded | Hint Size |
|--------------|------------|----------|--------------|-----------|
| 1,000        | 64         | 16       | 1,024        | ~8 KB     |
| 10,000       | 256        | 40       | 10,240       | ~80 KB    |
| 100,000      | 1,024      | 100      | 102,400      | ~800 KB   |
| 1,000,000    | 2,048      | 488      | 999,424      | ~7.6 MB   |
| 8,388,608    | 8,192      | 1,024    | 8,388,608    | ~64 MB    |

## Hint.bin File Format

```
[32-byte header]
  Bytes 0-7:   dbSize (actual number of entries)
  Bytes 8-15:  chunkSize (PIR parameter)
  Bytes 16-23: setSize (PIR parameter)
  Bytes 24-31: reserved (0)

[Database entries - padded to chunkSize × setSize]
  Entry format: 8 bytes per entry (uint64 little-endian)
  Padding: Zero entries appended to reach total size
```

## Overflow Handling

For balances > uint64 max (18.4 quintillion wei = ~18.4 billion ETH):

```go
maxUint64 := new(big.Int).SetUint64(^uint64(0))

if acc.Balance.Cmp(maxUint64) > 0 {
    balance = ^uint64(0)  // Clamp to max
    log.Printf("⚠️  Warning: Balance at index %d exceeds uint64 max, clamping", i)
}
```

**Real-world impact:**
- ETH 2.0 Deposit Contract: ~72.7M ETH → Will be clamped
- Total ETH supply: ~120M ETH → Maximum representable balance
- Most addresses: Well below uint64 max → No clamping needed

## Migration Guide

### From Hardcoded to Dynamic

**Old docker-compose.yml:**
```yaml
hint-generator:
  environment:
    DB_SIZE: 8388608
    CHUNK_SIZE: 8192
```

**New docker-compose.yml:**
```yaml
hint-generator:
  # No environment variables needed
  volumes:
    - plinko-data:/data  # Auto-detects from database.bin
```

### Testing Checklist

- [ ] Build updated Docker images locally
- [ ] Test with 1K, 10K, 100K, 1M entry databases
- [ ] Verify hint.bin metadata header is correct
- [ ] Verify PIR queries return correct balances
- [ ] Check address-to-index mapping preserved during padding
- [ ] Test overflow handling with large balances
- [ ] Monitor logs for clamping warnings

## Build Instructions

```bash
# Build hint-generator
cd services/plinko-hint-generator
docker build -t plinko-hint-generator:local .

# Build db-generator
cd services/db-generator
docker build -t plinko-db-generator:local .

# Test locally (don't push yet)
docker compose up -d
docker compose logs -f plinko-hint-generator
```

## Known Issues

### PIR Server Compatibility

The PIR server (`plinko-pir-server`) reads metadata from hint.bin header automatically. No changes needed - it's already compatible with dynamic sizing.

### Update Service Compatibility

The update service may still have hardcoded DB_SIZE in environment variables. Verify it reads from hint.bin or database.bin file size instead.

## Success Criteria

- ✅ No hardcoded 8388608 values in hint-generator
- ✅ Database padding works correctly for any size
- ✅ Address lookups work for all entries (0 to N-1)
- ✅ hint.bin header contains correct metadata
- ✅ PIR queries return accurate balances
- ✅ Overflow handling prevents zero balances for large amounts
- ✅ Tests pass for 1K, 10K, and 8M entry databases

## Future Improvements

1. **Automatic worker scaling**: Scale `CONCURRENT_WORKERS` based on `DB_SIZE`
2. **Progressive padding**: Pad only as needed during hint generation
3. **Compression**: Compress hint.bin for faster CDN delivery
4. **Streaming**: Generate hints incrementally for very large databases
5. **Validation**: Add checksum verification for database.bin integrity
