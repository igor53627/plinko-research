# Ethereum Mainnet Scaling Analysis

## Current Benchmark (5.6M entries, 171 MB)

| Metric | Value |
|--------|-------|
| Entries | 5,607,168 |
| Database size | 171 MB |
| Chunks | 684 |
| Chunk size | 8,192 |
| Hints | 43,776 |
| Hint generation time | **103 seconds** |
| Chunks/second | 6.6 |

## Ethereum Mainnet (87 GB uncompressed)

| Metric | Value |
|--------|-------|
| Database size | 87 GB |
| Entry size | 32 bytes |
| **Entries** | **2,919,235,584** (~2.9 billion) |
| Chunk size | 8,192 |
| **Chunks (setSize)** | **356,352** |
| **Hints** | **22,806,528** (~22.8M) |
| Hints buffer | **729 MB** |

## Time Extrapolation

Hint generation time scales linearly with number of chunks:

```
Scaling factor = 356,352 / 684 = 521×

Single-threaded time = 103s × 521 = 53,663 seconds
                     = 14.9 hours

With 8 Web Workers  = 14.9 hours / 8 = ~1.9 hours
```

## Memory Requirements (Streaming)

| Component | Size |
|-----------|------|
| Database chunk (streamed) | 256 KB per chunk |
| Hints buffer | 729 MB |
| IPRF state (1 instance at a time) | ~1 KB |
| **Total working memory** | **~750 MB** ✅ |

With streaming, we process one chunk at a time - no need to load 87 GB.

## Feasibility Analysis

### Streaming Architecture: ✅ Feasible

### Alternative Approaches

#### 1. Streaming Hint Generation
Process database in chunks from disk/network without loading entirely:

```
Time estimate: ~2 hours (with 8 workers)
Memory: ~1 GB (hints + working set)
Requires: Server-side streaming endpoint
```

#### 2. Server-Side Hint Generation
Server computes hints, client downloads encrypted:

```
Download: 729 MB (hints) + key exchange
Time: Minutes (download only)
Privacy: Requires blind key derivation
```

#### 3. Hierarchical Hints
Two-level structure - coarse hints for blocks, fine hints on-demand:

```
Level 1: ~10K chunks covering ~300K entries each
Level 2: Downloaded on-demand per query
Initial download: ~10 MB
Per-query: ~100 KB additional
```

#### 4. Incremental Updates Only
Start from genesis, apply all deltas:

```
Initial: No hints (zero state)
Updates: ~30 KB per block × 21M blocks = ~630 GB total
Not practical for bootstrap
```

## Recommended Approach

For 87 GB mainnet data:

1. **Server-side hint precomputation** with deterministic key derivation
2. Client downloads ~729 MB of pre-computed hints (one-time)
3. Incremental updates via delta mechanism (~30 KB/block)

### Implementation Sketch

```javascript
// Server generates hints using client's blinded key
async function serverSideHintGeneration() {
  // 1. Client sends blinded master key
  const blindedKey = blindKey(masterKey, blindingFactor);
  
  // 2. Server computes hints with blinded key
  // (Server can't learn original key)
  const encryptedHints = await serverComputeHints(blindedKey, database);
  
  // 3. Client downloads and unblinds
  const hints = unblindHints(encryptedHints, blindingFactor);
}
```

## Summary

| Scenario | Entries | Time | Memory | Feasible |
|----------|---------|------|--------|----------|
| Current (171 MB) | 5.6M | 103s | 171 MB | ✅ |
| Mainnet streaming (1 thread) | 2.9B | **~15 hours** | 750 MB | ✅ |
| Mainnet streaming (8 workers) | 2.9B | **~2 hours** | 750 MB | ✅ |
| With download overhead | 2.9B | **~3-4 hours** | 750 MB | ✅ |

## Streaming Implementation

```javascript
async function generateHintsStreaming(chunkUrls, numHints, chunkSize) {
  const hints = new Uint8Array(numHints * 32);
  const hintsU32 = new Uint32Array(hints.buffer);
  
  for (let alpha = 0; alpha < chunkUrls.length; alpha++) {
    // Stream one chunk at a time (256 KB)
    const chunkData = await fetchChunk(chunkUrls[alpha]);
    const chunkU32 = new Uint32Array(chunkData.buffer);
    
    // Create IPRF for this chunk only
    const iprf = new IPRF(deriveChunkKey(alpha), numHints, chunkSize);
    
    // Pre-compute inverse table
    const inverseTable = buildInverseTable(iprf, chunkSize, alpha);
    
    // XOR chunk data into hints
    for (let beta = 0; beta < chunkSize; beta++) {
      for (const hintIdx of inverseTable[beta]) {
        xorIntoHint(hintsU32, hintIdx, chunkU32, beta);
      }
    }
    
    // chunkData can be garbage collected now
    reportProgress(alpha, chunkUrls.length);
  }
  
  return hints;
}
```

## Network Considerations

| Factor | Impact |
|--------|--------|
| Download 87 GB (brotli 9 GB) | ~15-30 min at 10 MB/s |
| Processing 356K chunks | ~2 hours (8 workers) |
| Range requests overhead | Minimal (HTTP/2) |
| Resume support | ✅ Via chunk checkpointing |

**Total time**: ~2.5-3 hours for first-time setup

## Recommendation

Streaming with Web Workers is the best approach:
1. **Memory efficient**: Only 750 MB needed
2. **Resumable**: Can checkpoint progress per chunk
3. **Parallelizable**: 8 workers = 8x speedup
4. **No server trust**: Client computes own hints
