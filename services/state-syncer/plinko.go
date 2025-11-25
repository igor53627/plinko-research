package main

import (
	"time"
)

const (
	DBEntrySize   = 32 // Size of each database entry in bytes
	DBEntryLength = 4  // Number of uint64 values per database entry

	// Note: The current implementation assumes DBEntryLength = 4.
	// If this changes, the indexing logic in applyDatabaseUpdate and other
	// functions may need to be reviewed for correctness.
)

type DBEntry [DBEntryLength]uint64

// Plinko: Incremental Update System for Plinko PIR
// Based on ePrint 2024/318: "Single-Server PIR via Homomorphic Thorp Shuffles"
// Enables O(1) worst-case update time per database entry

// DBUpdate represents a single database entry update
type DBUpdate struct {
	Index    uint64  // Database index to update
	OldValue DBEntry // Previous value (for delta computation)
	NewValue DBEntry // New value to set
}

// HintDelta represents an incremental state update for the client
type HintDelta struct {
	Index uint64  // Database index that changed
	Delta DBEntry // XOR delta to apply
}

// PlinkoUpdateManager handles incremental database updates
type PlinkoUpdateManager struct {
	database     []uint64 // Reference to the database
	chunkSize    uint64
	setSize      uint64
	dbSize       uint64
}

// NewPlinkoUpdateManager creates a new update manager
func NewPlinkoUpdateManager(database []uint64, dbSize, chunkSize, setSize uint64) *PlinkoUpdateManager {
	return &PlinkoUpdateManager{
		database:     database,
		chunkSize:    chunkSize,
		setSize:      setSize,
		dbSize:       dbSize,
	}
}

// ApplyUpdates processes a batch of database updates and generates raw state deltas
//
// Algorithm:
//  1. For each updated database entry:
//     a. Compute XOR delta: delta = old_value ⊕ new_value
//     b. Generate HintDelta (renamed to StateDelta concept) containing the Index and Delta
//  2. Apply database updates
//  3. Return deltas for client
//
// Complexity: O(|updates|)
func (pm *PlinkoUpdateManager) ApplyUpdates(updates []DBUpdate) ([]HintDelta, time.Duration) {
	startTime := time.Now()

	deltas := make([]HintDelta, 0, len(updates))

	for _, update := range updates {
		// Step 1: Apply database update
		pm.applyDatabaseUpdate(update)

		// Step 2: Compute XOR delta
		var delta DBEntry
		for i := 0; i < DBEntryLength; i++ {
			delta[i] = update.OldValue[i] ^ update.NewValue[i]
		}

		// Step 3: Generate state delta
		// We no longer compute HintSetID here. The client will map Index -> HintSetID using their private key.
		deltas = append(deltas, HintDelta{
			Index: update.Index,
			Delta: delta,
		})
	}

	elapsed := time.Since(startTime)
	return deltas, elapsed
}

// applyDatabaseUpdate updates a single database entry
func (pm *PlinkoUpdateManager) applyDatabaseUpdate(update DBUpdate) {
	// Validate input
	if update.Index >= pm.dbSize {
		// Index out of valid range - skip
		return
	}

	// Calculate the starting position in the flat database array
	// Each DBEntry occupies DBEntryLength uint64 values
	startIdx := update.Index * DBEntryLength

	// Check bounds before proceeding
	if startIdx+DBEntryLength > uint64(len(pm.database)) {
		// Database array too small - skip
		return
	}

	// Copy new value to database
	for i := uint64(0); i < DBEntryLength; i++ {
		pm.database[startIdx+i] = update.NewValue[i]
	}
}
