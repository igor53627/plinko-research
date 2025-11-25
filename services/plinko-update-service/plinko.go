package main

import (
	"time"
)

// Plinko: Incremental Update System for Plinko PIR
// Based on ePrint 2024/318: "Single-Server PIR via Homomorphic Thorp Shuffles"
// Enables O(1) worst-case update time per database entry
//
// NOTE: iPRF is a CLIENT-SIDE operation. The server only needs to:
// 1. Track which database indices changed
// 2. Compute XOR deltas (old_value ⊕ new_value)
// 3. Publish deltas - clients apply them using their own iPRF

// DBUpdate represents a single database entry update
type DBUpdate struct {
	Index    uint64  // Database index to update
	OldValue DBEntry // Previous value (for delta computation)
	NewValue DBEntry // New value to set
}

// PublishedDelta represents a delta published to clients
// Clients use their local iPRF to determine which hints to update
type PublishedDelta struct {
	Index uint64  // Database index that changed
	Delta DBEntry // XOR delta: old_value ⊕ new_value
}

// PlinkoUpdateManager handles incremental database updates
type PlinkoUpdateManager struct {
	database  []uint64 // Reference to the database
	chunkSize uint64
	setSize   uint64
	dbSize    uint64
}

// NewPlinkoUpdateManager creates a new update manager
func NewPlinkoUpdateManager(database []uint64, dbSize, chunkSize, setSize uint64) *PlinkoUpdateManager {
	return &PlinkoUpdateManager{
		database:  database,
		chunkSize: chunkSize,
		setSize:   setSize,
		dbSize:    dbSize,
	}
}

// ApplyUpdates processes a batch of database updates and generates deltas for clients
//
// Algorithm:
//  1. For each updated database entry:
//     a. Compute XOR delta: delta = old_value ⊕ new_value
//     b. Apply update to database
//     c. Publish delta with index (clients use their iPRF to route it)
//
// Complexity: O(|updates|) with O(1) per update
func (pm *PlinkoUpdateManager) ApplyUpdates(updates []DBUpdate) ([]PublishedDelta, time.Duration) {
	startTime := time.Now()

	deltas := make([]PublishedDelta, 0, len(updates))

	for _, update := range updates {
		// Step 1: Compute XOR delta
		var delta DBEntry
		for i := 0; i < DBEntryLength; i++ {
			delta[i] = update.OldValue[i] ^ update.NewValue[i]
		}

		// Step 2: Apply database update
		pm.applyDatabaseUpdate(update)

		// Step 3: Publish delta with index
		// Client will use their local iPRF to determine affected hints
		deltas = append(deltas, PublishedDelta{
			Index: update.Index,
			Delta: delta,
		})
	}

	elapsed := time.Since(startTime)
	return deltas, elapsed
}

// applyDatabaseUpdate updates a single database entry
func (pm *PlinkoUpdateManager) applyDatabaseUpdate(update DBUpdate) {
	if update.Index >= pm.dbSize {
		return
	}

	startIdx := update.Index * DBEntryLength
	if startIdx+DBEntryLength > uint64(len(pm.database)) {
		return
	}

	for i := uint64(0); i < DBEntryLength; i++ {
		pm.database[startIdx+i] = update.NewValue[i]
	}
}
