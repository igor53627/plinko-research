import { describe, it, expect } from 'vitest';
import { Aes128 } from './aes128.js';
import prfVectors from '../testdata/prf_vectors.json';

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

const formatHex = (value) => value.toString(16).padStart(16, '0');

describe('AES-128 PRF vectors', () => {
  it('matches known ciphertext outputs', () => {
    const keyBytes = hexToUint8Array(prfVectors.key_hex);
    const aes = new Aes128(keyBytes);

    const block = new Uint8Array(16);
    const encrypted = new Uint8Array(16);
    const blockView = new DataView(block.buffer);
    const encryptedView = new DataView(encrypted.buffer);

    for (const vector of prfVectors.indices) {
      block.fill(0);
      blockView.setBigUint64(8, BigInt(vector.index));
      aes.encryptBlock(block, encrypted);
      const raw = encryptedView.getBigUint64(0, false);
      expect(formatHex(raw)).toBe(vector.raw_hex);
    }
  });
});