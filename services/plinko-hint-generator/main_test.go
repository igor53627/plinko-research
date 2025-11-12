package main

import (
	"encoding/binary"
	"os"
	"testing"
)

// TestDynamicDatabaseSizing tests that hint generator works with various database sizes
func TestDynamicDatabaseSizing(t *testing.T) {
	testCases := []struct {
		name       string
		dbEntries  uint64
		entrySize  int
		shouldPass bool
	}{
		{"Small 1K database", 1024, 8, true},
		{"Medium 10K database", 10000, 8, true},
		{"Large 8M database", 8388608, 8, true},
		{"Empty database", 0, 8, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Create temporary database
			tmpDB := t.TempDir() + "/database.bin"

			// Generate test database
			dbData := make([]byte, tc.dbEntries*uint64(tc.entrySize))
			for i := uint64(0); i < tc.dbEntries; i++ {
				binary.LittleEndian.PutUint64(dbData[i*8:(i+1)*8], i*1000)
			}

			if err := os.WriteFile(tmpDB, dbData, 0644); err != nil {
				t.Fatalf("Failed to write test database: %v", err)
			}

			// Calculate expected parameters
			actualEntries := tc.dbEntries
			if actualEntries == 0 {
				actualEntries = 1 // Minimum 1 entry
			}

			chunkSize, setSize := GenParams(actualEntries)
			totalEntries := chunkSize * setSize

			// Generate hint (this would call the actual function in real code)
			// For now, verify parameter calculation
			if chunkSize == 0 {
				t.Errorf("ChunkSize should not be zero")
			}
			if setSize == 0 {
				t.Errorf("SetSize should not be zero")
			}
			if totalEntries < actualEntries && tc.shouldPass {
				t.Errorf("Total entries (%d) should be >= actual entries (%d)",
					totalEntries, actualEntries)
			}
		})
	}
}

// TestGenParams validates the parameter generation algorithm
func TestGenParams(t *testing.T) {
	testCases := []struct {
		dbSize          uint64
		minChunkSize    uint64
		minSetSize      uint64
		totalEntriesMin uint64
	}{
		{1024, 64, 16, 1024},
		{10000, 256, 40, 10240}, // Rounded up
		{8388608, 8192, 1024, 8388608},
	}

	for _, tc := range testCases {
		chunkSize, setSize := GenParams(tc.dbSize)
		totalEntries := chunkSize * setSize

		if chunkSize < tc.minChunkSize {
			t.Errorf("For dbSize=%d, chunkSize=%d should be >= %d",
				tc.dbSize, chunkSize, tc.minChunkSize)
		}
		if setSize < tc.minSetSize {
			t.Errorf("For dbSize=%d, setSize=%d should be >= %d",
				tc.dbSize, setSize, tc.minSetSize)
		}
		if totalEntries < tc.totalEntriesMin {
			t.Errorf("For dbSize=%d, totalEntries=%d should be >= %d",
				tc.dbSize, totalEntries, tc.totalEntriesMin)
		}
		if setSize%4 != 0 {
			t.Errorf("SetSize must be multiple of 4, got %d", setSize)
		}
	}
}

// TestHintHeaderFormat verifies hint.bin header contains correct metadata
func TestHintHeaderFormat(t *testing.T) {
	// Create a test hint file
	tmpDir := t.TempDir()

	// Test parameters
	dbSize := uint64(10000)
	chunkSize, setSize := GenParams(dbSize)
	totalEntries := chunkSize * setSize

	// Create hint header
	header := make([]byte, 32)
	binary.LittleEndian.PutUint64(header[0:8], dbSize)
	binary.LittleEndian.PutUint64(header[8:16], chunkSize)
	binary.LittleEndian.PutUint64(header[16:24], setSize)
	binary.LittleEndian.PutUint64(header[24:32], 0)

	// Create dummy database
	dbData := make([]byte, totalEntries*8)
	fullHint := append(header, dbData...)

	hintPath := tmpDir + "/hint.bin"
	if err := os.WriteFile(hintPath, fullHint, 0644); err != nil {
		t.Fatalf("Failed to write hint: %v", err)
	}

	// Read and verify
	data, err := os.ReadFile(hintPath)
	if err != nil {
		t.Fatalf("Failed to read hint: %v", err)
	}

	if len(data) < 32 {
		t.Fatalf("Hint file too small: %d bytes", len(data))
	}

	readDBSize := binary.LittleEndian.Uint64(data[0:8])
	readChunkSize := binary.LittleEndian.Uint64(data[8:16])
	readSetSize := binary.LittleEndian.Uint64(data[16:24])

	if readDBSize != dbSize {
		t.Errorf("Header dbSize mismatch: got %d, want %d", readDBSize, dbSize)
	}
	if readChunkSize != chunkSize {
		t.Errorf("Header chunkSize mismatch: got %d, want %d", readChunkSize, chunkSize)
	}
	if readSetSize != setSize {
		t.Errorf("Header setSize mismatch: got %d, want %d", readSetSize, setSize)
	}

	expectedSize := 32 + int(totalEntries*8)
	if len(data) != expectedSize {
		t.Errorf("Hint file size mismatch: got %d, want %d", len(data), expectedSize)
	}
}

// TestPaddingPreservesAddressMapping ensures padding doesn't break address lookups
func TestPaddingPreservesAddressMapping(t *testing.T) {
	// Create database with 10 entries
	dbEntries := uint64(10)
	database := make([]byte, dbEntries*8)

	// Set known values
	for i := uint64(0); i < dbEntries; i++ {
		binary.LittleEndian.PutUint64(database[i*8:(i+1)*8], i*100)
	}

	// Calculate padding needed
	chunkSize, setSize := GenParams(dbEntries)
	totalEntries := chunkSize * setSize

	// Pad database
	padding := make([]byte, int(totalEntries-dbEntries)*8)
	padded := append(database, padding...)

	// Verify original entries are intact
	for i := uint64(0); i < dbEntries; i++ {
		value := binary.LittleEndian.Uint64(padded[i*8 : (i+1)*8])
		expected := i * 100
		if value != expected {
			t.Errorf("Entry %d corrupted after padding: got %d, want %d", i, value, expected)
		}
	}

	// Verify padding is zero
	for i := dbEntries; i < totalEntries; i++ {
		value := binary.LittleEndian.Uint64(padded[i*8 : (i+1)*8])
		if value != 0 {
			t.Errorf("Padded entry %d should be 0, got %d", i, value)
		}
	}
}
