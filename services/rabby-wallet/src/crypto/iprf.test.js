import { describe, it, expect } from 'vitest';
import { IPRF } from './iprf.js';

const hexToUint8Array = (hex) => {
  if (hex.length % 2 !== 0) {
    throw new Error('Hex string must have even length');
  }
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
};

describe('IPRF Invertibility', () => {
  it('should correctly invert forward evaluations', () => {
    // 32-byte key
    const keyHex = "000102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f";
    const key = hexToUint8Array(keyHex);
    
    const n = 1024; // Domain
    const m = 256;  // Range
    
    const iprf = new IPRF(key, n, m);
    
    // Test a subset of inputs
    for (let x = 0; x < n; x++) {
      const y = iprf.forward(x);
      
      // Check range bounds
      expect(y).toBeGreaterThanOrEqual(0);
      expect(y).toBeLessThan(m);
      
      const preimages = iprf.inverse(y);
      
      // Check if x is in preimages (cast BigInt from inverse back to Number or compare loose)
      const found = preimages.some(val => Number(val) === x);
      if (!found) {
        console.error(`Failed to find inverse for x=${x} -> y=${y}. Preimages:`, preimages);
      }
      expect(found).toBe(true);
    }
  });
});

describe('IPRF Determinism', () => {
  it('should produce same output for same key', () => {
    const keyHex = "000102030405060708090a0b0c0d0e0f000102030405060708090a0b0c0d0e0f";
    const key = hexToUint8Array(keyHex);
    
    const iprf1 = new IPRF(key, 100, 64);
    const iprf2 = new IPRF(key, 100, 64);
    
    for (let i = 0; i < 100; i++) {
      expect(iprf1.forward(i)).toBe(iprf2.forward(i));
    }
  });
});
