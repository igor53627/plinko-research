# Reference Implementation Alignment

This document describes the alignment of the local Plinko PIR implementation with the reference implementation at `plinko-extractor`, specifically the Coq specification in `Plinko.v`.

## Overview

The Plinko PIR system has been updated to match the formal specification from the Plinko paper (EUROCRYPT 2025, eprint 2024/318). Key changes include:

1. **Swap-or-Not PRP** replacing 4-round Feistel network
2. **Full hint lifecycle** with regular, backup, and promoted hints
3. **Proper domain separation** in cryptographic primitives
4. **Deterministic subset generation** for hint block selection

## Cryptographic Components

### Swap-or-Not PRP (`swap-or-not-prp.js`)

Implements the Morris-Rogaway Swap-or-Not construction (eprint 2013/560) for small-domain pseudorandom permutations.

**Key properties:**
- **Rounds**: `6 * ceil(log₂(N+1)) + 6` (matches `Plinko.v` line 191-193)
- **Involution**: Each round is self-inverse, enabling efficient inversion
- **Domain separation**: Tag bytes distinguish `deriveRoundKey` (0x00) and `prfBit` (0x01)

```javascript
// Partner computation (matches Plinko.v line 179-182)
computePartner(roundKey, x) {
  return (roundKey + domainSize - x) % domainSize;
}

// Each round: swap with partner if PRF(round, max(x, partner)) = 1
swapOrNotRound(round, x) {
  const partner = this.computePartner(this.roundKeys[round], x);
  const canonical = x > partner ? x : partner;
  return this.prfBit(round, canonical) === 1 ? partner : x;
}
```

**Why Swap-or-Not over Feistel?**
- Provable security for small domains (vs heuristic security)
- Exact match with Coq formal specification
- Self-inverse rounds simplify implementation

### iPRF v2 (`iprf-v2.js`)

Invertible PRF built from Swap-or-Not PRP + PMNS (Pseudorandom Multinomial Sampler).

**Composition:**
```
forward(x) = PMNS(PRP(x))
inverse(y) = { PRP⁻¹(z) : z ∈ PMNS⁻¹(y) }
```

This matches `Plinko.v` lines 231-265.

**SubsetGenerator:**
Deterministic random subset generation using AES-based PRF for hint block selection.

```javascript
// Generate exactly `size` elements from [0, total-1]
generate(seed, size, total) → Set<number>

// Early-termination membership check
contains(seed, size, total, blockIdx) → boolean
```

## Hint Structures

### Three Hint Types (matches Plinko.v lines 268-296)

| Type | Structure | Size | Purpose |
|------|-----------|------|---------|
| **RegularHint** | `(P_j, p_j)` | `\|P_j\| = c/2 + 1` | Primary query hints |
| **BackupHint** | `(B_j, ℓ_j, r_j)` | `\|B_j\| = c/2` | Replacement pool |
| **PromotedHint** | `(P_j, x, p_j)` | Variable | Former backup after query |

### Hint Lifecycle

```
┌─────────────────┐     consume      ┌─────────────────┐
│  RegularHint    │ ───────────────▶ │   (consumed)    │
│  (P_j, p_j)     │                  │                 │
└─────────────────┘                  └─────────────────┘
                                              │
                              promote         │
        ┌─────────────────────────────────────┘
        │
        ▼
┌─────────────────┐                  ┌─────────────────┐
│  BackupHint     │ ───────────────▶ │  PromotedHint   │
│  (B_j, ℓ_j, r_j)│                  │  (P_j, x, p_j)  │
└─────────────────┘                  └─────────────────┘
```

### Promotion Logic

When a regular hint is consumed for query at index `queryIdx`:

1. Find next available backup hint `(B_j, ℓ_j, r_j)`
2. Compute `α = floor(queryIdx / w)` (query block)
3. If `α ∈ B_j`:
   - `promotedBlocks = B_j`
   - `promotedParity = r_j ⊕ value` (use outside parity)
4. If `α ∉ B_j`:
   - `promotedBlocks = complement(B_j)`
   - `promotedParity = ℓ_j ⊕ value` (use inside parity)

## PlinkoClientState

Full client state management implementing `Plinko.v` algorithms:

### Key Operations

| Method | Plinko.v Reference | Description |
|--------|-------------------|-------------|
| `initializeHints()` | HintInit (line 343-427) | Create empty hints with random subsets |
| `processEntry(i, v)` | HintInit streaming | Update parities during DB streaming |
| `getHint(α, β)` | GetHint (line 433-486) | Find hint for entry via iPRF inversion |
| `consumeHint()` | Query/Recon | Mark used, cache result, promote backup |
| `updateHint(i, δ)` | UpdateHint (line 493-541) | XOR delta into affected hints |

### Key Derivation

Uses AES-based key derivation with "PLNK" domain tag for proper separation:

```javascript
deriveBlockKey(masterKey, blockIdx) {
  // Input: blockIdx || "PLNK" || counter
  // Output: AES(masterKey, input₀) || AES(masterKey, input₁)
}
```

## Security Considerations

### Privacy-Preserving Shuffle

The `getHint()` method shuffles candidate hints using `crypto.getRandomValues()` (not `Math.random()`) to prevent timing-based leakage of which hint was selected.

### Domain Separation

All AES-based PRF calls include domain tags:
- Round key derivation: `0x00`
- PRF bit evaluation: `0x01`
- Block key derivation: "PLNK" (0x504C4E4B)

### Hint Coverage

With `λw` regular hints and `c/2 + 1` blocks per hint, each entry is covered by approximately `O(λ)` hints, ensuring high availability.

## Files

| File | Description |
|------|-------------|
| `services/rabby-wallet/src/crypto/swap-or-not-prp.js` | Swap-or-Not PRP |
| `services/rabby-wallet/src/crypto/iprf-v2.js` | iPRF + SubsetGenerator |
| `services/rabby-wallet/src/crypto/plinko-hints.js` | Hint structures + state |
| `services/rabby-wallet/src/crypto/*.test.js` | 50 tests covering all components |

## References

- **Coq spec**: `plinko-extractor/docs/Plinko.v`
- **Paper algorithms**: `plinko-extractor/docs/plinko_paper_part6_algorithms.json`
- **Morris-Rogaway Swap-or-Not**: eprint 2013/560
- **Plinko paper**: eprint 2024/318
