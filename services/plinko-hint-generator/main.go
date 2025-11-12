package main

import (
	"encoding/binary"
	"log"
	"math"
	"os"
	"time"
)

const (
	DatabasePath = "/data/database.bin"
	HintPath     = "/data/hint.bin"

	DBEntrySize = 52 // 52 bytes per entry (20 byte address + 32 byte uint256 balance)
)

// GenParams generates Plinko PIR parameters (ChunkSize, SetSize)
// Same logic as Plinko PIR util.GenParams
func GenParams(dbSize uint64) (uint64, uint64) {
	targetChunkSize := uint64(2 * math.Sqrt(float64(dbSize)))
	chunkSize := uint64(1)
	for chunkSize < targetChunkSize {
		chunkSize *= 2
	}
	setSize := uint64(math.Ceil(float64(dbSize) / float64(chunkSize)))
	// Round up to the next multiple of 4
	setSize = (setSize + 3) / 4 * 4
	return chunkSize, setSize
}

func main() {
	log.Println("========================================")
	log.Println("Plinko PIR Hint Generator")
	log.Println("========================================")

	// Wait for database.bin to exist
	waitForDatabase()

	// Read database.bin to determine actual size
	log.Println("Reading database.bin...")
	startRead := time.Now()
	database, err := readDatabase()
	if err != nil {
		log.Fatalf("Failed to read database: %v", err)
	}
	log.Printf("Read %d bytes in %v\n", len(database), time.Since(startRead))

	// Calculate actual database size from file
	actualDBSize := uint64(len(database) / DBEntrySize)
	log.Printf("Database size: %d entries (%.1f MB)\n", actualDBSize, float64(len(database))/1024/1024)
	log.Println()

	// Calculate Plinko PIR parameters based on actual size
	chunkSize, setSize := GenParams(actualDBSize)
	totalEntries := chunkSize * setSize

	log.Printf("Plinko PIR Parameters:\n")
	log.Printf("  Chunk Size: %d\n", chunkSize)
	log.Printf("  Set Size: %d\n", setSize)
	log.Printf("  Total Entries: %d (padded from %d)\n", totalEntries, actualDBSize)
	log.Println()

	// Pad database to totalEntries if needed
	if actualDBSize < totalEntries {
		log.Printf("Padding database from %d to %d entries...\n",
			actualDBSize, totalEntries)
		padding := make([]byte, int(totalEntries)*DBEntrySize-len(database))
		database = append(database, padding...)
	}

	// Generate hint.bin with Piano format
	log.Println("Generating hint.bin...")
	startGen := time.Now()
	if err := generateHint(database, actualDBSize, chunkSize, setSize); err != nil {
		log.Fatalf("Failed to generate hint: %v", err)
	}
	log.Printf("Generated hint.bin in %v\n", time.Since(startGen))

	// Verify output
	verifyOutput(actualDBSize)

	log.Println()
	log.Println("✅ Hint generation complete!")
	log.Printf("Total time: %v\n", time.Since(startRead))
}

func waitForDatabase() {
	log.Println("Waiting for database.bin...")
	for i := 0; i < 60; i++ {
		if _, err := os.Stat(DatabasePath); err == nil {
			log.Println("✅ database.bin found")
			return
		}
		if i%5 == 0 {
			log.Printf("  Waiting... (%d/60s)\n", i)
		}
		time.Sleep(1 * time.Second)
	}
	log.Fatal("Timeout waiting for database.bin")
}

func readDatabase() ([]byte, error) {
	return os.ReadFile(DatabasePath)
}

func generateHint(database []byte, dbSize, chunkSize, setSize uint64) error {
	f, err := os.Create(HintPath)
	if err != nil {
		return err
	}
	defer f.Close()

	// Write Plinko PIR metadata header (32 bytes)
	// Format: [DBSize:8][ChunkSize:8][SetSize:8][Reserved:8]
	header := make([]byte, 32)
	binary.LittleEndian.PutUint64(header[0:8], dbSize)
	binary.LittleEndian.PutUint64(header[8:16], chunkSize)
	binary.LittleEndian.PutUint64(header[16:24], setSize)
	binary.LittleEndian.PutUint64(header[24:32], 0) // Reserved

	if _, err := f.Write(header); err != nil {
		return err
	}

	// Write database in Piano chunked format
	// The database is already in the correct format (sequential entries)
	// Plinko PIR chunks it logically: chunk i = entries [i*chunkSize : (i+1)*chunkSize]
	if _, err := f.Write(database); err != nil {
		return err
	}

	return nil
}

func verifyOutput(dbSize uint64) {
	info, err := os.Stat(HintPath)
	if err != nil {
		log.Printf("⚠️  Could not stat hint.bin: %v\n", err)
		return
	}

	// Expected size: 32 bytes header + (chunkSize * setSize * 8 bytes)
	chunkSize, setSize := GenParams(dbSize)
	expectedSize := 32 + int64(chunkSize*setSize*DBEntrySize)

	sizeMB := float64(info.Size()) / 1024 / 1024

	if info.Size() == expectedSize {
		log.Printf("✅ hint.bin: %d bytes (%.1f MB) - correct size\n", info.Size(), sizeMB)
	} else {
		log.Printf("⚠️  hint.bin: %d bytes (%.1f MB) - expected %d bytes\n",
			info.Size(), sizeMB, expectedSize)
	}

	// Dynamic size check - hint should be reasonable for database size
	log.Printf("✅ Hint size: %.1f MB for %d entries\n", sizeMB, dbSize)
}
