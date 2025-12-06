# Plinko PIR Research Implementation

> Private Information Retrieval using invertible Pseudorandom Functions (iPRF) based on the Plinko paper (EUROCRYPT 2025)

## Overview

Plinko is a single-server Private Information Retrieval (PIR) protocol with efficient updates. This implementation provides a production-ready system for private blockchain state queries.

**Key Features:**
- **Privacy-Preserving**: Query blockchain state without revealing query contents
- **Private Delta Updates**: Clients apply updates locally using private iPRF keys—server never learns which hints a client has
- **High Performance**: O(log m + k) query complexity with iPRF inverse (m = range size, k = result set size)
- **Efficient Updates**: Incremental state updates without full reconstruction
- **Real Data**: 10% mainnet slice (3M accounts, 366MB) for realistic testing

## Quick Start

### Docker Compose (Fastest - 5 minutes)

```bash
git clone https://github.com/igor53627/plinko-pir-research.git
cd plinko-pir-research

# Start all services
make build && make start

# Access the demo wallet
open http://localhost:5173
```

**What you get:**
- Rabby wallet fork with "Privacy Mode" toggle
- 3M real Ethereum accounts (10% mainnet slice from block #23,889,314)
- Live Plinko PIR decoding visualization
- Real-time delta updates every 12 seconds

## Architecture

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│  Rabby Wallet   │ ───▶ │  PIR Server      │ ───▶ │  State Syncer   │
│  (Privacy Mode) │ ◀─── │  (Query Handler) │ ◀─── │  (iPRF Updates) │
└─────────────────┘      └──────────────────┘      └─────────────────┘
                                                            │
                                                            ▼
                                                    ┌───────────────┐
                                                    │ Ethereum Node │
                                                    └───────────────┘
```

### Core Components

| Service | Purpose | Technology |
|---------|---------|------------|
| **eth-mock** | Simulated Ethereum node | Anvil (Foundry) |
| **plinko-update-service** | Monitors blocks, generates deltas (Deprecated) | Go + WebSocket |
| **state-syncer** | Streams Hypersync blocks → snapshots/deltas | Go + Hypersync RPC |
| **plinko-pir-server** | Handles PIR queries | Plinko protocol |
| **cdn-mock** | Distributes snapshot packages/deltas + proxies IPFS | Nginx / CloudFlare R2 |
| **rabby-wallet** | Privacy-enhanced wallet UI | React + Vite |
| **ipfs** | Local Kubo daemon (pin snapshots) | ipfs/kubo |

## Privacy Model

Plinko achieves privacy through two mechanisms:

### 1. Private Queries
The client sends a query `(P, offsets)` where P is a random subset of blocks. The server computes XOR parities but cannot determine which specific entry the client wants (it's hidden among ~half the blocks).

### 2. Private Delta Updates
**Key insight**: The server publishes raw deltas `(index, XOR_value)` to all clients identically. Each client applies deltas locally using their **private iPRF keys**:

```
Server publishes:  (index=42, delta=0xABC...)
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
      Client A        Client B        Client C
      keys[α].inverse(β)  →  different hint sets!
```

- Server learns nothing about which entries clients care about
- Each client's iPRF keys are unique (derived from their master key)
- Same database index maps to **different hints** for each client

See [docs/reference-alignment.md](docs/reference-alignment.md) for implementation details.

## Performance

**iPRF Inverse (Production):**
- Domain size: 8.4M accounts (PoC Scale)
- Range size: 1024 bins
- Inverse time: **50µs** (O(log m + k))
- Speedup: **1200× faster** than brute force (60ms)

**TablePRP:**
- Forward/Inverse: **O(1)** with ~0.55ns per operation
- Memory: 16 bytes per element (~134MB for 8.4M)

**Plinko Update Performance:**
```
Traditional PIR (SimplePIR):
  Update 2,000 accounts: ~1,875ms (database regeneration)

Plinko PIR:
  Update 2,000 accounts: ~24µs (XOR deltas)

Speedup: ~78,000× faster ⚡
```

This makes Plinko the **first PIR system viable for real-time blockchain synchronization** (12-second Ethereum blocks).

## Testing

### Go Tests

```bash
cd services/state-syncer
go test -v ./...
# 87/87 tests passing (100%)
```

**Key Innovation**: First PIR system achieving real-time blockchain sync (79× faster updates than SimplePIR)

## Documentation

Documentation has been moved to the `plinko-pir-docs` repository.

- **[Reference Alignment](docs/reference-alignment.md)**: Alignment with Plinko.v Coq specification
- **[iPRF Optimization](docs/iprf-optimization.md)**: 87x speedup via normal approximation
- **[Hint Generation](docs/hint-generation-optimization.md)**: Hint generation optimizations
- **[Query Compression](docs/query-compression.md)**: Query size reduction techniques

### Cryptographic Components

| Component | Description | Location |
|-----------|-------------|----------|
| **Swap-or-Not PRP** | Morris-Rogaway small-domain PRP | `services/rabby-wallet/src/crypto/swap-or-not-prp.js` |
| **iPRF v2** | Invertible PRF (PRP + PMNS) | `services/rabby-wallet/src/crypto/iprf-v2.js` |
| **Plinko Hints** | Full hint lifecycle management | `services/rabby-wallet/src/crypto/plinko-hints.js` |

## Research Paper

Implementation based on:
> **Plinko: Single-Server PIR with Efficient Updates via Invertible PRFs**
> Alexander Hoover, Sarvar Patel, Giuseppe Persiano, Kevin Yeo
> EUROCRYPT 2025
> [eprint.iacr.org/2024/318](https://eprint.iacr.org/2024/318)

Paper available in the documentation repository.

## Deployment

Plinko PIR ships as a Docker Compose reference stack:

```bash
make build && make start    # builds services + starts docker compose
make logs                   # tail logs per service
make clean                  # tear down containers + volumes
```

**Resources**: 4 GB RAM, 2 CPU cores

### Remote Deployment

See the Deployment Guide in the documentation repository for the fully scripted Vultr deployment workflow powered by `scripts/vultr-deploy.sh`.

### Database

The repository includes a 10% slice of real Ethereum mainnet state:

| File | Size | Description |
|------|------|-------------|
| `data/database.bin` | 366 MB | 12M entries (3M accounts × 3 words + 3M storage slots) |
| `data/account-mapping.bin` | 69 MB | Address → index lookup (3M accounts) |
| `data/metadata.json` | ~200 B | Block #23,889,314 extraction metadata |

See [data/README.md](data/README.md) for entry layout and usage.

**For full mainnet database**, use [plinko-extractor](https://github.com/igor53627/plinko-extractor):
```bash
plinko-extractor --db-path /path/to/reth/db --output-dir ./data
```

## Development

For detailed development instructions, see [DEVELOPMENT.md](DEVELOPMENT.md).

### Prerequisites

```bash
# Docker & Docker Compose
docker --version  # >= 20.10
docker compose version  # >= 2.0
```

### Build and Test

```bash
# Clone repository
git clone https://github.com/igor53627/plinko-pir-research.git
cd plinko-pir-research

# Start services
make build
make start

# Run tests
make test

# View logs
make logs

# Stop services
make stop
```

## License

MIT License - see [LICENSE](LICENSE) file

## Contact & Links

- **GitHub**: https://github.com/igor53627/plinko-pir-research
- **Plinko Paper**: https://eprint.iacr.org/2024/318
- **Vitalik's Plinko Tutorial**: https://vitalik.eth.limo/general/2025/11/25/plinko.html
- **Issues**: https://github.com/igor53627/plinko-pir-research/issues

---

*Bringing information-theoretic privacy to Ethereum, one query at a time.* 🔐
