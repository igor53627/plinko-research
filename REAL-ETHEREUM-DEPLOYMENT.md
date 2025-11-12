# Plinko PIR - Real Ethereum Data Deployment Guide

## Summary

Successfully generated **real Ethereum mainnet balance data** for Plinko PIR system. The database contains 38 top Ethereum addresses (exchanges, DAOs, DeFi protocols) with actual mainnet balances, padded to 10,000 entries.

## Generated Files

### Database Files (in `./data/`)
- **`database.bin`** (273 KB)
  - 10,000 entries: 38 real addresses + 9,962 padding addresses
  - Format: sorted (address, balance) pairs
  - 20-byte address + 8-byte balance (uint64 little-endian)

- **`address-mapping.bin`** (234 KB)
  - Index mapping for efficient lookups
  - Format: 20-byte address + 4-byte offset

### Real Addresses Included

Top Ethereum addresses with real mainnet balances (as of block 23,781,279):

| Address | Balance | Description |
|---------|---------|-------------|
| `0x00000000219ab540356cBB839Cbe05303d7705Fa` | 72,724,007 ETH | Ethereum 2.0 Deposit Contract |
| `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | 2,404,363 ETH | WETH Contract |
| `0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8` | 1,996,008 ETH | Binance 7 |
| `0x40B38765696e3d5d8d9d834D8AaD4bB6e418E489` | 1,177,795 ETH | Bitfinex |
| `0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503` | 554,999 ETH | Binance-Peg |
| `0xF977814e90dA44bFA03b6295A0616a897441aceC` | 538,622 ETH | Binance Hot Wallet |
| `0x8103683202aa8DA10536036EDef04CDd865C225E` | 275,000 ETH | Huobi |
| ... and 31 more real addresses |

All balances can be verified on Etherscan.

## Generation Method

### 1. Data Source
- **Method**: Direct RPC queries to Reth (Ethereum execution client)
- **RPC**: http://localhost:8656 on reth-onion-dev server
- **Block Height**: ~23,781,279 (November 12, 2025)
- **Source**: Ethereum mainnet via local Reth node

### 2. Address Selection
- Top exchanges: Binance, Bitfinex, Coinbase, Kraken, Crypto.com, OKX, Huobi
- Major contracts: ETH 2.0 Deposit, WETH, USDT/USDC treasuries
- DeFi protocols: 1inch, Uniswap
- Known whales and DAOs

### 3. Generation Script
Location: `/tmp/plinko-real-eth/generate_from_known_addresses.py`

```bash
# Run on reth-onion-dev:
cd /tmp/plinko-real-eth
python3 generate_from_known_addresses.py

# Output:
# - database.bin
# - address-mapping.bin
```

## Deployment Configuration

### New Docker Compose File

Created `deploy/vm/docker-compose-static.yml`:

**Key Changes:**
1. ✅ **Removed**: `eth-mock` (Anvil) - not needed with static data
2. ✅ **Removed**: `db-generator` - database already generated
3. ✅ **Kept**: `hint-generator` - generates PIR hints from static database
4. ✅ **Updated**: `update-service` - uses public RPC (https://eth.llamarpc.com)
5. ✅ **Kept**: `pir-server`, `cdn-mock`, `rabby-wallet`

### Services Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Static Data (Real Ethereum Mainnet Balances)               │
│  - database.bin (273 KB)                                    │
│  - address-mapping.bin (234 KB)                             │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ├──> hint-generator (run once) ──> hint.bin
                   │
                   ├──> pir-server (PIR queries)
                   │
                   └──> update-service (mainnet RPC) ──> deltas/
                          │
                          └──> Public RPC: eth.llamarpc.com
```

## Deployment Steps

### When VM is Accessible

```bash
# 1. Copy database files to VM
scp -r data/*.bin root@108.61.75.100:/root/plinko-pir-deploy/data/

# 2. Copy new docker-compose configuration
scp deploy/vm/docker-compose-static.yml root@108.61.75.100:/root/plinko-pir-deploy/

# 3. SSH to VM and deploy
ssh root@108.61.75.100
cd /root/plinko-pir-deploy

# 4. Stop old deployment
docker compose down

# 5. Start with static real data
docker compose -f docker-compose-static.yml up -d

# 6. Monitor hint generation (should take ~30-60 seconds)
docker compose -f docker-compose-static.yml logs -f hint-generator

# 7. Check service status
docker compose -f docker-compose-static.yml ps
```

### Expected Services

```
NAME                      STATUS
plinko-hint-generator     Exited (0)    ✅ Completed successfully
plinko-update-service     Up (healthy)  ✅ Tracking mainnet updates
plinko-pir-server         Up (healthy)  ✅ Ready for PIR queries
plinko-cdn-mock           Up            ✅ Serving hint.bin & deltas
plinko-rabby-wallet       Up            ✅ Wallet UI accessible
```

## Testing with Real Addresses

### Test Addresses (Verifiable on Etherscan)

1. **ETH 2.0 Deposit Contract** (72.7M ETH)
   ```
   Address: 0x00000000219ab540356cBB839Cbe05303d7705Fa
   Etherscan: https://etherscan.io/address/0x00000000219ab540356cBB839Cbe05303d7705Fa
   Expected Balance: 72,724,007 ETH
   ```

2. **WETH Contract** (2.4M ETH)
   ```
   Address: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
   Etherscan: https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
   Expected Balance: 2,404,363 ETH
   ```

3. **Binance 7** (2M ETH)
   ```
   Address: 0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8
   Etherscan: https://etherscan.io/address/0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8
   Expected Balance: 1,996,008 ETH
   ```

4. **Bitfinex** (1.2M ETH)
   ```
   Address: 0x40B38765696e3d5d8d9d834D8AaD4bB6e418E489
   Etherscan: https://etherscan.io/address/0x40B38765696e3d5d8d9d834D8AaD4bB6e418E489
   Expected Balance: 1,177,795 ETH
   ```

### Testing Steps

1. **Open Wallet**
   ```
   http://108.61.75.100
   ```

2. **Test Privacy Mode (PIR)**
   - Enter address: `0x00000000219ab540356cBB839Cbe05303d7705Fa`
   - Enable "Privacy Mode" toggle
   - Click "Query Balance"
   - Expected: **72,724,007 ETH** via PIR
   - Decoding visualization should appear

3. **Test Non-Privacy Mode (Direct RPC)**
   - Enter same address
   - Disable "Privacy Mode"
   - Click "Query Balance"
   - Expected: Same balance via direct RPC (eth.llamarpc.com)

4. **Verify Against Etherscan**
   - Open: https://etherscan.io/address/0x00000000219ab540356cBB839Cbe05303d7705Fa
   - Compare balance with PIR result
   - Should match (within ~12 seconds due to block time)

## Current Status

✅ **Completed:**
- Real Ethereum database generated (38 top addresses, 10K total entries)
- Database files: `database.bin` (273 KB), `address-mapping.bin` (234 KB)
- Generation script created: `generate_from_known_addresses.py`
- Docker Compose configuration updated: `docker-compose-static.yml`
- All files ready in `./data/` directory

⏸️ **Pending VM Access:**
- VM at 108.61.75.100 currently unreachable (SSH timeout)
- Deployment ready when VM is accessible
- All files prepared and tested locally

## Files Locations

### Local Files (Ready for Deployment)
```
./data/database.bin                      # 273 KB - Real Ethereum balances
./data/address-mapping.bin               # 234 KB - Address index
./deploy/vm/docker-compose-static.yml    # Updated deployment config
/tmp/plinko-real-eth/generate_from_known_addresses.py  # Generation script
```

### VM Deployment (When Accessible)
```
/root/plinko-pir-deploy/
├── data/
│   ├── database.bin          # Copy from local
│   ├── address-mapping.bin   # Copy from local
│   └── deltas/              # Generated by update-service
├── docker-compose-static.yml # Copy from local
└── config/
    └── nginx.conf           # Existing (reverse proxy)
```

## Next Steps

1. **Verify VM Accessibility**
   ```bash
   ssh root@108.61.75.100
   # If fails: Check VM status, IP address, firewall
   ```

2. **Deploy When Ready**
   - Follow deployment steps above
   - Monitor hint-generator logs
   - Test with real addresses

3. **Update Documentation**
   - Update README.md with real data deployment info
   - Document test addresses and expected results

## Notes

- **Balance Accuracy**: Balances are from block ~23,781,279 (Nov 12, 2025)
- **Update Service**: Tracks new mainnet blocks via public RPC
- **Delta Files**: Update-service generates incremental updates for changed balances
- **Privacy**: PIR queries are information-theoretically private
- **Verification**: All addresses can be verified on Etherscan

## Troubleshooting

### If Hint Generation Fails
```bash
# Check database files exist
ls -lh /root/plinko-pir-deploy/data/*.bin

# Manually run hint generator
docker run --rm \
  -v /root/plinko-pir-deploy/data:/data \
  -e DB_SIZE=10000 \
  -e CHUNK_SIZE=2896 \
  ghcr.io/igor53627/plinko-hint-generator:latest
```

### If Update Service Can't Connect to RPC
```bash
# Check RPC connectivity
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  https://eth.llamarpc.com

# Update RPC URL if needed
export RPC_URL=https://eth.drpc.org
docker compose -f docker-compose-static.yml up -d update-service
```

### If Balances Don't Match
- Balances change over time due to new transactions
- Allow ~12 seconds for blockchain updates
- Verify against Etherscan for current state

---

**Generated**: November 12, 2025
**Block Height**: ~23,781,279
**Network**: Ethereum Mainnet
**Data Source**: Local Reth Node (reth-onion-dev)
