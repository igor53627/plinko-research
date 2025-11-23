package main

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
)

func TestDerivePlinkoParams(t *testing.T) {
	tests := []struct {
		name        string
		dbEntries   uint64
		wantChunk   uint64
		wantSetSize uint64
	}{
		{"small_db", 16, 8, 4},
		{"non_power_of_two", 23, 16, 4},
		{"large_db", 8388608, 8192, 1024},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			chunk, setSize := derivePlinkoParams(tt.dbEntries)
			if chunk != tt.wantChunk {
				t.Fatalf("chunk size mismatch: got %d want %d", chunk, tt.wantChunk)
			}
			if setSize != tt.wantSetSize {
				t.Fatalf("set size mismatch: got %d want %d", setSize, tt.wantSetSize)
			}
		})
	}
}

func TestLoadServerFromDatabase(t *testing.T) {
	tmp := t.TempDir()
	path := filepath.Join(tmp, "database.bin")

	var data []byte
	for i := uint64(0); i < 10; i++ {
		// Create a 32-byte entry (4 uint64s)
		// We put the value in the first uint64
		var buf [32]byte
		binary.LittleEndian.PutUint64(buf[0:8], i+1)
		// The other 3 uint64s are zero
		data = append(data, buf[:]...)
	}

	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatalf("failed writing db file: %v", err)
	}

	server := loadServer(path)

	if server.dbSize != 10 {
		t.Fatalf("dbSize mismatch: got %d want 10", server.dbSize)
	}

	expectedChunk, expectedSet := derivePlinkoParams(10)
	if server.chunkSize != expectedChunk {
		t.Fatalf("chunkSize mismatch: got %d want %d", server.chunkSize, expectedChunk)
	}
	if server.setSize != expectedSet {
		t.Fatalf("setSize mismatch: got %d want %d", server.setSize, expectedSet)
	}

	totalEntries := expectedChunk * expectedSet
	// server.database stores flattened uint64s, so length is totalEntries * DBEntryLength
	if uint64(len(server.database)) != totalEntries*DBEntryLength {
		t.Fatalf("database length mismatch: got %d want %d", len(server.database), totalEntries*DBEntryLength)
	}

	for i := 0; i < 10; i++ {
		// We only set the first word of each entry
		if server.database[i*DBEntryLength] != uint64(i+1) {
			t.Fatalf("entry %d mismatch: got %d want %d", i, server.database[i*DBEntryLength], i+1)
		}
	}

	// Check padding (entries 10 to totalEntries-1)
	for i := 10; uint64(i) < totalEntries; i++ {
		for w := 0; w < DBEntryLength; w++ {
			if server.database[i*DBEntryLength+w] != 0 {
				t.Fatalf("padding entry %d word %d expected zero got %d", i, w, server.database[i*DBEntryLength+w])
			}
		}
	}
}