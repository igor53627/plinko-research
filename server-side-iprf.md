# Plinko: Privacy-Preserving State Updates via Raw Deltas

This document explains the architecture of the **Raw Delta Update Mechanism** used in the Plinko State Syncer service to ensure query privacy while maintaining efficient incremental updates.

## The Problem: Shared Hints & Privacy

In a standard Plinko PIR setup, clients generate private hints (parities of random subsets of the database) to query privately.

The original "Shared Hint" proposal suggested that the server and all clients share a single IPRF key to define these subsets. This would allow the server to broadcast efficient "Hint Updates" (e.g., "Hint #42 changed by V").

**However, this approach is insecure.**
If the server knows the hint structure (the key), it can de-anonymize any query. When a client sends a query set $P = S_k \setminus \{\alpha\}$, the server can simply compare $P$ against the known set $S_k$ to identify the missing element $\alpha$ (the target).

## The Solution: Raw Deltas + Private Mapping

To preserve privacy, the server **must not know** which accounts map to which hint sets on the client side. Therefore, the server broadcasts **Raw State Changes**, and clients map them to their own private hints.

### 1. Server Architecture (State Syncer)

The server is "stateless" regarding PIR. It simply tracks changes in the underlying blockchain state.

*   **Input**: Ethereum Blocks (transactions, state changes).
*   **Process**:
    1.  Detects changes in account balances.
    2.  Computes the XOR difference: $\Delta = \text{NewBalance} \oplus \text{OldBalance}$.
    3.  Broadcasts a **Raw Delta Record**: `(AccountIndex, DeltaValue)`.
*   **Output**: A stream of compact delta files (e.g., `delta-123456.bin`).

**Format:**
```go
type StateDelta struct {
    Index uint64  // Database index of the account (8 bytes)
    Delta [4]uint64 // XOR difference (32 bytes)
}
// Total size: 40 bytes per update
```

### 2. Client Architecture (Rabby Wallet)

The client maintains **Private Hints** generated from a local secret key.

*   **Setup**:
    1.  Client generates a random secret key $K$.
    2.  Client downloads a snapshot of the database.
    3.  Client generates local hints using $K$: $Hint_j = \bigoplus_{i \in S_j} D[i]$.

*   **Processing Updates**:
    1.  Client receives a Raw Delta: `(AccountIndex #123, Value V)`.
    2.  Client calculates which of its *private* hint sets contain Account #123.
        *   $S_{affected} = \text{IPRF}_K^{-1}(\text{AccountIndex})$.
    3.  Client updates those specific local hints:
        *   For each $h \in S_{affected}$: $Hint[h] = Hint[h] \oplus V$.

### 3. Privacy Guarantees

*   **Update Phase**: The server knows "Account #123 changed". This is public blockchain data. The server **does not know** that the client mapped Account #123 to "Hint #99".
*   **Query Phase**: When the client queries "Hint #99", the server sees a random request. Since the server doesn't know the composition of "Hint #99" (it depends on the client's secret $K$), it cannot infer which element is missing.

## Performance Trade-offs

| Metric | Shared Hints (Insecure) | Raw Deltas (Secure) |
| :--- | :--- | :--- |
| **Privacy** | ❌ Broken | ✅ **Information-Theoretic** |
| **Server Memory** | High (Needs Index Map) | **Low** (Stateless) |
| **Bandwidth** | 48 bytes/update | **40 bytes/update** |
| **Client CPU** | Low (Array Access) | Moderate (IPRF per update) |

The **Raw Delta** approach is superior in every metric except Client CPU, which remains negligible for typical blockchain update rates (~500 updates/block).
