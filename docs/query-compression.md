# Plinko PIR Query Compression

## Overview

This document describes techniques for compressing Plinko PIR queries without breaking the cryptographic protocol. All compression is **lossless** - the server receives exact values after decompression.

## Current Query Format

```javascript
// Uncompressed query (~2.5 KB)
{
  p: number[],        // Block indices in P\{α}, ~342 integers (0-683)
  offsets: number[]   // IPRF outputs for each block, 684 integers (0-8191)
}
```

## Compression Stack

```
┌─────────────────────────────────────────────────────────┐
│  Original Query                                         │
│  p: [0,2,5,7,12,...] (342 integers)                     │  ~2.5 KB
│  offsets: [123,456,789,...] (684 integers)              │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Semantic Encoding                             │
│  • P as bitmap: 684 bits = 86 bytes                     │  ~1.2 KB
│  • Offsets as varint array                              │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 2: General Compression (zstd/pako)               │  ~600-800 bytes
└─────────────────────────────────────────────────────────┘
```

## Implementation

### Shared Codec (Client + Server)

```javascript
// query-codec.js - Used by BOTH client and server

/**
 * Encode P as a bitmap
 * @param {number[]} p - Array of block indices
 * @param {number} setSize - Total number of blocks (e.g., 684)
 * @returns {Uint8Array} - Bitmap representation
 */
export function encodePBitmap(p, setSize) {
  const bytes = Math.ceil(setSize / 8);
  const bitmap = new Uint8Array(bytes);
  for (const idx of p) {
    bitmap[idx >> 3] |= (1 << (idx & 7));
  }
  return bitmap;
}

/**
 * Decode bitmap back to array of indices
 * @param {Uint8Array} bitmap
 * @param {number} setSize
 * @returns {number[]}
 */
export function decodePBitmap(bitmap, setSize) {
  const p = [];
  for (let i = 0; i < setSize; i++) {
    if (bitmap[i >> 3] & (1 << (i & 7))) {
      p.push(i);
    }
  }
  return p;
}

/**
 * Encode offsets using variable-length integers
 * Each offset is 0-8191 (13 bits), so we use 2-byte encoding
 * @param {number[]} offsets
 * @returns {Uint8Array}
 */
export function encodeOffsetsVarint(offsets) {
  // Simple 2-byte little-endian encoding (offsets fit in 16 bits)
  const buffer = new Uint8Array(offsets.length * 2);
  const view = new DataView(buffer.buffer);
  for (let i = 0; i < offsets.length; i++) {
    view.setUint16(i * 2, offsets[i], true);
  }
  return buffer;
}

/**
 * Decode varint offsets
 * @param {Uint8Array} buffer
 * @returns {number[]}
 */
export function decodeOffsetsVarint(buffer) {
  const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
  const offsets = [];
  for (let i = 0; i < buffer.length / 2; i++) {
    offsets.push(view.getUint16(i * 2, true));
  }
  return offsets;
}

/**
 * Compress query for transmission
 * @param {Object} query - { p: number[], offsets: number[] }
 * @param {number} setSize - Total blocks (684)
 * @returns {Uint8Array} - Compressed query
 */
export function compressQuery(query, setSize) {
  const pBitmap = encodePBitmap(query.p, setSize);
  const offsetsEncoded = encodeOffsetsVarint(query.offsets);
  
  // Combine: [2 bytes: pBitmap length][pBitmap][offsetsEncoded]
  const combined = new Uint8Array(2 + pBitmap.length + offsetsEncoded.length);
  const view = new DataView(combined.buffer);
  view.setUint16(0, pBitmap.length, true);
  combined.set(pBitmap, 2);
  combined.set(offsetsEncoded, 2 + pBitmap.length);
  
  // Optional: Apply zstd/pako compression
  // return pako.deflate(combined);
  return combined;
}

/**
 * Decompress query on server
 * @param {Uint8Array} compressed
 * @param {number} setSize
 * @returns {Object} - { p: number[], offsets: number[] }
 */
export function decompressQuery(compressed, setSize) {
  // Optional: Decompress zstd/pako first
  // const combined = pako.inflate(compressed);
  const combined = compressed;
  
  const view = new DataView(combined.buffer, combined.byteOffset, combined.byteLength);
  const pBitmapLen = view.getUint16(0, true);
  
  const pBitmap = combined.slice(2, 2 + pBitmapLen);
  const offsetsEncoded = combined.slice(2 + pBitmapLen);
  
  return {
    p: decodePBitmap(pBitmap, setSize),
    offsets: decodeOffsetsVarint(offsetsEncoded)
  };
}
```

### Client-Side Usage

```javascript
// In plinko-pir-client.js

import { compressQuery } from './query-codec.js';

async queryBalancePrivate(address) {
  // ... build query as before ...
  
  const query = {
    p: finalP,
    offsets: finalOffsets
  };
  
  // Compress before sending
  const compressed = compressQuery(query, this.metadata.setSize);
  
  const response = await fetch(`${this.pirServerUrl}/query/plinko`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/octet-stream',
      'X-Query-Encoding': 'plinko-v1'  // Signal compression format
    },
    body: compressed
  });
  
  // ... rest of query handling ...
}
```

### Server-Side Usage

```go
// In Go server

import "github.com/yourorg/plinko/codec"

func handlePlinkoQuery(w http.ResponseWriter, r *http.Request) {
    encoding := r.Header.Get("X-Query-Encoding")
    
    body, _ := io.ReadAll(r.Body)
    
    var p []int
    var offsets []int
    
    if encoding == "plinko-v1" {
        // Decompress
        p, offsets = codec.DecompressQuery(body, setSize)
    } else {
        // Legacy JSON format
        json.Unmarshal(body, &query)
        p = query.P
        offsets = query.Offsets
    }
    
    // Process query - math is IDENTICAL
    parity := computeParity(p, offsets)
    // ...
}
```

## Compression Ratios

| Component | Original | Compressed | Ratio |
|-----------|----------|------------|-------|
| P (342 indices) | ~1.4 KB (JSON) | 86 bytes (bitmap) | **16x** |
| Offsets (684 ints) | ~2.7 KB (JSON) | 1.4 KB (uint16) | **2x** |
| **Total** | **~4 KB** | **~1.5 KB** | **2.7x** |
| + zstd | ~1.5 KB | ~600 bytes | **6.5x** |

## Why This Doesn't Break the Math

1. **Lossless**: Every compression step is reversible
2. **Exact Values**: Server gets identical `p` and `offsets` arrays
3. **Transport Layer**: Compression happens outside crypto protocol

```
Client                          Server
   │                               │
   │  compress(query)              │
   │  ─────────────────────────►   │
   │                               │  decompress(data)
   │                               │  
   │                               │  // Exact same values!
   │                               │  parity = XOR(blocks[p], offsets)
   │                               │
   │  ◄─────────────────────────   │
   │         response              │
```

## Adding zstd Compression (Optional)

For additional ~50% compression:

```javascript
// Client (browser)
import { compress, decompress } from 'fflate';  // or pako

export function compressQueryWithZstd(query, setSize) {
  const encoded = compressQuery(query, setSize);
  return compress(encoded);
}

export function decompressQueryWithZstd(compressed, setSize) {
  const encoded = decompress(compressed);
  return decompressQuery(encoded, setSize);
}
```

```go
// Server (Go)
import "github.com/klauspost/compress/zstd"

func decompressQueryWithZstd(data []byte, setSize int) ([]int, []int) {
    decoder, _ := zstd.NewReader(nil)
    decoded, _ := decoder.DecodeAll(data, nil)
    return DecompressQuery(decoded, setSize)
}
```

## Backward Compatibility

The server should support both formats:

```go
func handleQuery(r *http.Request) {
    contentType := r.Header.Get("Content-Type")
    
    switch contentType {
    case "application/octet-stream":
        // New compressed format
        handleCompressedQuery(r)
    case "application/json":
        // Legacy JSON format
        handleJSONQuery(r)
    }
}
```

## Summary

| Question | Answer |
|----------|--------|
| Client changes needed? | Yes - compress before send |
| Server changes needed? | Yes - decompress before process |
| Breaks crypto? | No - lossless encoding |
| Can combine techniques? | Yes - bitmap + varint + zstd |
| Backward compatible? | Yes - with content-type detection |
