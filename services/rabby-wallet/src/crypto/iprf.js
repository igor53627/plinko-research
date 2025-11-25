import { FastAes128 } from './aes128-fast.js';

export class IPRF {
  constructor(key, n, m) {
    if (key.length !== 32) throw new Error("IPRF key must be 32 bytes");
    
    const key1 = key.slice(0, 16);
    const key2 = key.slice(16, 32);
    
    this.prp = new FeistelPRP(key1, n);
    this.pmns = new PMNS(key2, n, m);
  }

  forward(x) {
    const permuted = this.prp.permute(BigInt(x));
    return this.pmns.forward(permuted);
  }

  inverse(y) {
    const preimages = this.pmns.backward(BigInt(y));
    return preimages.map(val => this.prp.inverse(val));
  }
  
  domainSize() {
    return this.prp.n;
  }
  
  rangeSize() {
    return this.pmns.m;
  }
}

class FeistelPRP {
  constructor(key, n) {
    this.block = new FastAes128(key);
    this.n = BigInt(n);
    
    let bits = 0;
    let p2 = 1n;
    while (p2 < this.n) {
      p2 <<= 1n;
      bits++;
    }
    if (bits % 2 !== 0) bits++;
    if (bits < 2) bits = 2;
    
    this.bits = bits;
  }

  permute(x) {
    x = BigInt(x);
    if (x >= this.n) return x;

    while (true) {
      x = this.feistelEncrypt(x);
      if (x < this.n) return x;
    }
  }

  inverse(y) {
    y = BigInt(y);
    if (y >= this.n) return y;

    while (true) {
      y = this.feistelDecrypt(y);
      if (y < this.n) return y;
    }
  }

  feistelEncrypt(val) {
    const halfBits = BigInt(this.bits / 2);
    const lowerMask = (1n << halfBits) - 1n;
    
    let left = (val >> halfBits) & lowerMask;
    let right = val & lowerMask;

    for (let i = 0; i < 4; i++) {
      const tmp = right;
      const f = this.roundFunc(i, right);
      right = left ^ (f & lowerMask);
      left = tmp;
    }
    
    return (left << halfBits) | right;
  }

  feistelDecrypt(val) {
    const halfBits = BigInt(this.bits / 2);
    const lowerMask = (1n << halfBits) - 1n;
    
    let left = (val >> halfBits) & lowerMask;
    let right = val & lowerMask;

    for (let i = 3; i >= 0; i--) {
      const tmp = left;
      const f = this.roundFunc(i, left);
      left = right ^ (f & lowerMask);
      right = tmp;
    }
    
    return (left << halfBits) | right;
  }

  roundFunc(round, input) {
    const data = new Uint8Array(16);
    const view = new DataView(data.buffer);
    
    // Little endian put uint64
    view.setBigUint64(0, input, true);
    view.setBigUint64(8, BigInt(round), true);
    
    const out = new Uint8Array(16);
    this.block.encryptBlock(data, out);
    
    const outView = new DataView(out.buffer);
    return outView.getBigUint64(0, true);
  }
}

class PMNS {
  constructor(key, n, m) {
    if (n <= 0 || m <= 0) throw new Error("PMNS requires n > 0 and m > 0");
    
    // Check power of 2 for m
    // BigInt checks: (m & (m-1)) === 0
    const mBig = BigInt(m);
    if ((mBig & (mBig - 1n)) !== 0n) {
        throw new Error("PMNS currently assumes m is a power of two for Plinko parameters");
    }

    this.block = new FastAes128(key);
    this.n = BigInt(n);
    this.m = mBig;
  }

  forward(x) {
    x = BigInt(x);
    let node = { start: 0n, count: this.n, low: 0n, high: this.m - 1n };
    
    while (node.low < node.high) {
      const { left: leftNode, right: rightNode } = this.children(node);
      
      if (x < node.start + leftNode.count) {
        node = leftNode;
      } else {
        node = rightNode;
      }
    }
    return Number(node.low);
  }

  backward(y) {
    y = BigInt(y);
    let node = { start: 0n, count: this.n, low: 0n, high: this.m - 1n };
    
    while (node.low < node.high) {
      const { left: leftNode, right: rightNode } = this.children(node);
      const mid = (node.high + node.low) / 2n;
      
      if (y <= mid) {
        node = leftNode;
      } else {
        node = rightNode;
      }
    }
    
    const result = [];
    for (let i = 0n; i < node.count; i++) {
      result.push(node.start + i);
    }
    return result;
  }

  children(node) {
    const mid = (node.high + node.low) / 2n;
    const leftBins = mid - node.low + 1n;
    const totalBins = node.high - node.low + 1n;
    
    // leftBins/totalBins is always 0.5 for power of 2 m
    const p = Number(leftBins) / Number(totalBins);
    
    const leftCount = this.sampleBinomial(node.count, p, node.low, node.high);
    
    const left = {
      start: node.start,
      count: leftCount,
      low: node.low,
      high: mid
    };
    
    const right = {
      start: node.start + leftCount,
      count: node.count - leftCount,
      low: mid + 1n,
      high: node.high
    };
    
    return { left, right };
  }

  sampleBinomial(n, p, low, high) {
    if (n === 0n) return 0n;
    
    const seed = new Uint8Array(16);
    const seedView = new DataView(seed.buffer);
    seedView.setBigUint64(0, low, true);
    seedView.setBigUint64(8, high, true);
    
    const input = new Uint8Array(16);
    input.set(seed);
    const inputView = new DataView(input.buffer);
    
    const output = new Uint8Array(16);
    const outputView = new DataView(output.buffer); // Reused in loop via encryptBlock
    
    let successes = 0n;
    const isHalf = Math.abs(p - 0.5) < 0.000001;
    
    let processed = 0n;
    let counter = 0n;
    
    while (processed < n) {
      // perturb input: standard counter mode
      // input[0..8] = counter, input[8..16] = high part of seed (nonce)
      inputView.setBigUint64(0, counter, true);
      // high part (bytes 8-15) remains constant from seed
      
      this.block.encryptBlock(input, output);
      counter++;
      
      // Process 16 bytes
      for (let i = 0; i < 16 && processed < n; i++) {
        if (isHalf) {
          // Count bits
          const val = output[i];
          for (let b = 0; b < 8 && processed < n; b++) {
            if ((val & (1 << b)) !== 0) {
              successes++;
            }
            processed++;
          }
        } else {
          // Generic case: 4 bytes -> float
          if (i + 4 <= 16) {
            const rndVal = outputView.getUint32(i, true);
            const rndFloat = rndVal / 4294967296.0; // 2^32
            if (rndFloat < p) {
              successes++;
            }
            processed++;
            i += 3;
          }
        }
      }
    }
    
    return successes;
  }
}