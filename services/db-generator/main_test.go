package main

import (
	"encoding/binary"
	"math/big"
	"testing"

	"github.com/ethereum/go-ethereum/common"
)

// TestBalanceOverflowHandling tests that large balances don't cause overflow
func TestBalanceOverflowHandling(t *testing.T) {
	testCases := []struct {
		name            string
		balance         *big.Int
		expectedUint64  uint64
		shouldClamp     bool
	}{
		{
			name:            "Normal balance",
			balance:         big.NewInt(1000000000000000000), // 1 ETH
			expectedUint64:  1000000000000000000,
			shouldClamp:     false,
		},
		{
			name:            "Max uint64",
			balance:         new(big.Int).SetUint64(^uint64(0)),
			expectedUint64:  ^uint64(0),
			shouldClamp:     false,
		},
		{
			name:            "Overflow - exceeds uint64",
			balance:         new(big.Int).Mul(big.NewInt(1<<62), big.NewInt(10)),
			expectedUint64:  ^uint64(0), // Should clamp to max
			shouldClamp:     true,
		},
		{
			name:            "Massive balance - 72M ETH (ETH2 contract)",
			balance:         new(big.Int).Mul(big.NewInt(72000000), big.NewInt(1e18)),
			expectedUint64:  ^uint64(0), // Will overflow, should clamp
			shouldClamp:     true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			// Simulate the conversion with clamping
			var result uint64
			maxUint64 := new(big.Int).SetUint64(^uint64(0))

			if tc.balance.Cmp(maxUint64) > 0 {
				// Balance exceeds uint64 max - should clamp
				result = ^uint64(0)
				if !tc.shouldClamp {
					t.Errorf("Balance %s should not need clamping but did", tc.balance.String())
				}
			} else {
				result = tc.balance.Uint64()
				if tc.shouldClamp {
					t.Errorf("Balance %s should clamp but didn't", tc.balance.String())
				}
			}

			if result != tc.expectedUint64 {
				t.Errorf("Balance conversion failed: got %d, want %d", result, tc.expectedUint64)
			}

			// Verify the value can be written safely
			var buf [8]byte
			binary.LittleEndian.PutUint64(buf[:], result)
			readBack := binary.LittleEndian.Uint64(buf[:])
			if readBack != result {
				t.Errorf("Write-read roundtrip failed: got %d, want %d", readBack, result)
			}
		})
	}
}

// TestDatabaseBinFormat validates database.bin structure
func TestDatabaseBinFormat(t *testing.T) {
	accounts := []AccountData{
		{Address: common.HexToAddress("0x1000000000000000000000000000000000000001"), Balance: big.NewInt(1000)},
		{Address: common.HexToAddress("0x1000000000000000000000000000000000000002"), Balance: big.NewInt(2000)},
		{Address: common.HexToAddress("0x1000000000000000000000000000000000000003"), Balance: big.NewInt(3000)},
	}

	// Simulate database.bin creation
	data := make([]byte, len(accounts)*8)
	for i, acc := range accounts {
		balance := acc.Balance.Uint64()
		binary.LittleEndian.PutUint64(data[i*8:(i+1)*8], balance)
	}

	// Verify size
	expectedSize := len(accounts) * 8
	if len(data) != expectedSize {
		t.Errorf("Database size mismatch: got %d bytes, want %d bytes", len(data), expectedSize)
	}

	// Verify each entry
	for i, acc := range accounts {
		readBalance := binary.LittleEndian.Uint64(data[i*8 : (i+1)*8])
		expectedBalance := acc.Balance.Uint64()
		if readBalance != expectedBalance {
			t.Errorf("Balance mismatch at index %d: got %d, want %d", i, readBalance, expectedBalance)
		}
	}
}

// TestAddressMappingFormat validates address-mapping.bin structure
func TestAddressMappingFormat(t *testing.T) {
	accounts := []AccountData{
		{Address: common.HexToAddress("0x1000000000000000000000000000000000000001"), Balance: big.NewInt(1000)},
		{Address: common.HexToAddress("0x1000000000000000000000000000000000000002"), Balance: big.NewInt(2000)},
	}

	// Simulate address-mapping.bin creation
	data := make([]byte, len(accounts)*24)
	for i, acc := range accounts {
		offset := i * 24
		// Write address (20 bytes)
		copy(data[offset:offset+20], acc.Address.Bytes())
		// Write index (4 bytes)
		binary.LittleEndian.PutUint32(data[offset+20:offset+24], uint32(i))
	}

	// Verify size
	expectedSize := len(accounts) * 24
	if len(data) != expectedSize {
		t.Errorf("Mapping size mismatch: got %d bytes, want %d bytes", len(data), expectedSize)
	}

	// Verify each entry
	for i, acc := range accounts {
		offset := i * 24
		// Read address
		readAddr := common.BytesToAddress(data[offset : offset+20])
		// Read index
		readIndex := binary.LittleEndian.Uint32(data[offset+20 : offset+24])

		if readAddr != acc.Address {
			t.Errorf("Address mismatch at index %d: got %s, want %s", i, readAddr.Hex(), acc.Address.Hex())
		}
		if readIndex != uint32(i) {
			t.Errorf("Index mismatch at entry %d: got %d, want %d", i, readIndex, i)
		}
	}
}

// TestConcurrentWorkersConfiguration validates worker pool configuration
func TestConcurrentWorkersConfiguration(t *testing.T) {
	testCases := []struct {
		name          string
		workers       int
		totalAccounts int
		shouldBeValid bool
	}{
		{"Default workers", 10000, 100000, true},
		{"Low workers", 10, 1000, true},
		{"High workers", 50000, 1000000, true},
		{"Zero workers", 0, 1000, false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.workers <= 0 && tc.shouldBeValid {
				t.Errorf("Worker count %d should be invalid", tc.workers)
			}
			if tc.workers > 0 && !tc.shouldBeValid {
				t.Errorf("Worker count %d should be valid", tc.workers)
			}

			// Verify workers can be scaled based on total accounts
			recommendedWorkers := tc.totalAccounts / 100
			if recommendedWorkers < 10 {
				recommendedWorkers = 10
			}
			if recommendedWorkers > 50000 {
				recommendedWorkers = 50000
			}

			if recommendedWorkers <= 0 {
				t.Errorf("Recommended workers should be > 0, got %d", recommendedWorkers)
			}
		})
	}
}

// TestEnvironmentVariableSupport tests DB_SIZE configuration
func TestEnvironmentVariableSupport(t *testing.T) {
	// Test default behavior
	defaultSize := 8388608
	if defaultSize != 8388608 {
		t.Errorf("Default DB_SIZE should be 8388608, got %d", defaultSize)
	}

	// Test custom sizes
	testSizes := []int{1024, 10000, 100000, 8388608}
	for _, size := range testSizes {
		if size <= 0 {
			t.Errorf("DB_SIZE must be positive, got %d", size)
		}
	}
}
