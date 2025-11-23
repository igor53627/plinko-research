import { describe, it, expect } from 'vitest';
import { Aes128 } from './aes128.js';
import prfVectors from '../testdata/prf_vectors.json';
import { hexToUint8Array } from './__test-utils__.js';

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