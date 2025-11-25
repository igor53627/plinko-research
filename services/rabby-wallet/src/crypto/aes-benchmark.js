/**
 * AES Benchmark: Compare original vs T-table optimized
 * 
 * Run with: node --experimental-vm-modules src/crypto/aes-benchmark.js
 */

import { Aes128 } from './aes128.js';
import { FastAes128 } from './aes128-fast.js';

const ITERATIONS = 100000;

// Generate random key and input
const key = new Uint8Array(16);
const input = new Uint8Array(16);
const output = new Uint8Array(16);

for (let i = 0; i < 16; i++) {
  key[i] = Math.floor(Math.random() * 256);
  input[i] = Math.floor(Math.random() * 256);
}

// Create instances
const aesOriginal = new Aes128(key);
const aesFast = new FastAes128(key);

// Warmup
for (let i = 0; i < 1000; i++) {
  aesOriginal.encryptBlock(input, output);
  aesFast.encryptBlock(input, output);
}

// Verify correctness
const out1 = new Uint8Array(16);
const out2 = new Uint8Array(16);
aesOriginal.encryptBlock(input, out1);
aesFast.encryptBlock(input, out2);

let match = true;
for (let i = 0; i < 16; i++) {
  if (out1[i] !== out2[i]) {
    match = false;
    console.error(`Mismatch at byte ${i}: ${out1[i]} vs ${out2[i]}`);
  }
}

if (match) {
  console.log('✅ Output matches between implementations');
} else {
  console.error('❌ Output mismatch!');
  process.exit(1);
}

// Benchmark original
console.log(`\nBenchmarking ${ITERATIONS.toLocaleString()} encryptions...`);

const startOriginal = performance.now();
for (let i = 0; i < ITERATIONS; i++) {
  aesOriginal.encryptBlock(input, output);
}
const endOriginal = performance.now();
const timeOriginal = endOriginal - startOriginal;

// Benchmark fast
const startFast = performance.now();
for (let i = 0; i < ITERATIONS; i++) {
  aesFast.encryptBlock(input, output);
}
const endFast = performance.now();
const timeFast = endFast - startFast;

// Results
const opsOriginal = ITERATIONS / (timeOriginal / 1000);
const opsFast = ITERATIONS / (timeFast / 1000);
const speedup = timeOriginal / timeFast;

console.log(`
┌─────────────────────────────────────────────────┐
│           AES-128 Benchmark Results             │
├─────────────────────────────────────────────────┤
│ Original (naive):                               │
│   Time: ${timeOriginal.toFixed(2)} ms                              │
│   Speed: ${(opsOriginal / 1000).toFixed(1)}K ops/sec                         │
│   Throughput: ${((opsOriginal * 16) / 1024 / 1024).toFixed(1)} MB/s                       │
├─────────────────────────────────────────────────┤
│ Fast (T-table):                                 │
│   Time: ${timeFast.toFixed(2)} ms                              │
│   Speed: ${(opsFast / 1000).toFixed(1)}K ops/sec                         │
│   Throughput: ${((opsFast * 16) / 1024 / 1024).toFixed(1)} MB/s                       │
├─────────────────────────────────────────────────┤
│ Speedup: ${speedup.toFixed(2)}x                                │
└─────────────────────────────────────────────────┘
`);
