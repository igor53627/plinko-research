# Plinko PIR Database (10% Slice)

Real Ethereum state data extracted from mainnet, sliced for development and testing.

## Dataset Summary

| Metric | Value |
|--------|-------|
| Source Block | #23,889,314 |
| Accounts | 3,000,000 |
| Storage Slots | 3,000,000 |
| Total Entries (N) | 12,000,000 |
| Database Size | 366 MB |
| Entry Size | 32 bytes |

## Files

| File | Size | Description |
|------|------|-------------|
| `database.bin` | 366 MB | Flat array of 32-byte words |
| `account-mapping.bin` | 69 MB | Address → index lookup (24 bytes each) |
| `metadata.json` | ~200 B | Extraction metadata |

## Entry Layout

Each **account** occupies 3 consecutive entries (96 bytes total):
- Entry 0: Nonce (uint64, zero-padded to 32 bytes)
- Entry 1: Balance (uint256, 32 bytes LE)
- Entry 2: Bytecode Hash (bytes32)

Each **storage slot** occupies 1 entry (32 bytes):
- Value (uint256, 32 bytes LE)

## Account Mapping Format

Each mapping entry is 24 bytes:
- Bytes 0-19: Ethereum address (20 bytes)
- Bytes 20-23: Database index (uint32 LE)

To look up an account's balance:
1. Binary search `account-mapping.bin` for the address
2. Extract the 4-byte index at offset 20
3. Query database entry at `index * 3 + 1` (balance is the second word)

## Server Parameters

When loaded by `plinko-pir-server`:
- **ChunkSize**: 8,192 entries
- **SetSize**: 1,468 chunks
- Derived via `derivePlinkoParams(12000000)`

## Origin

10% slice of the [plinko-extractor regression-test-data](https://github.com/igor53627/plinko-extractor/pull/6):
```bash
# Database: first 12M entries (10% of 120M)
head -c 384000000 database_full.bin > database.bin

# Accounts: first 3M accounts (10% of 30M)
head -c 72000000 account-mapping.bin > account-mapping.bin
```

## Usage

```bash
# Start server with local database
DATABASE_PATH=./data/database.bin go run ./services/plinko-pir-server

# Or via Docker Compose (mounts ./data to /data)
make start

# Test query
curl "http://localhost:3000/query/plaintext?index=1"
# Returns: {"value":"14133900649480422907630","server_time_nanos":292}
```
