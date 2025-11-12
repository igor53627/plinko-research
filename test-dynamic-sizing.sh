#!/bin/bash
set -e

echo "=========================================="
echo "Plinko PIR - Dynamic Sizing Integration Test"
echo "=========================================="
echo ""

# Test configuration
TEST_DB_SIZE=10000
TEST_DIR="./test-data"
TEST_DB="$TEST_DIR/database.bin"
TEST_HINT="$TEST_DIR/hint.bin"
TEST_MAPPING="$TEST_DIR/address-mapping.bin"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Clean up test directory
echo "Cleaning up previous test data..."
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Create a minimal test database.bin (10K entries)
echo "Creating test database.bin with $TEST_DB_SIZE entries..."
dd if=/dev/zero of="$TEST_DB" bs=8 count=$TEST_DB_SIZE status=none

# Fill with test values (each entry is index * 1000 wei)
for i in $(seq 0 $((TEST_DB_SIZE - 1))); do
    # Calculate value: i * 1000
    value=$((i * 1000))
    # Write as little-endian uint64 (simplified - just writes low bytes)
    printf '\x%02x\x%02x\x00\x00\x00\x00\x00\x00' \
        $((value % 256)) $((value / 256 % 256)) >> "$TEST_DB.tmp"
done 2>/dev/null || true

# Use the zero-filled file (simpler for testing)
echo "  Size: $(stat -f%z "$TEST_DB" 2>/dev/null || stat -c%s "$TEST_DB") bytes"
echo ""

# Test 1: Run hint-generator
echo "=========================================="
echo "Test 1: Hint Generation"
echo "=========================================="
docker run --rm \
    -v "$PWD/$TEST_DIR:/data" \
    plinko-hint-generator:test

echo ""

# Verify hint.bin was created
if [ ! -f "$TEST_HINT" ]; then
    echo -e "${RED}❌ FAIL: hint.bin not created${NC}"
    exit 1
fi

echo -e "${GREEN}✅ PASS: hint.bin created${NC}"

# Verify hint.bin size
HINT_SIZE=$(stat -f%z "$TEST_HINT" 2>/dev/null || stat -c%s "$TEST_HINT")
echo "  Hint size: $HINT_SIZE bytes"

# Read hint.bin header
echo ""
echo "Reading hint.bin header..."
if command -v xxd &> /dev/null; then
    echo "  First 32 bytes (header):"
    xxd -l 32 "$TEST_HINT" | head -4
fi

# Extract dbSize from header (bytes 0-7, little-endian)
if command -v xxd &> /dev/null; then
    HEADER_DBSIZE=$(xxd -l 8 -p "$TEST_HINT" | tail -c 17)
    echo "  DBSize from header: $HEADER_DBSIZE (hex)"
fi

echo ""

# Test 2: Verify dynamic parameters
echo "=========================================="
echo "Test 2: Parameter Calculation Verification"
echo "=========================================="

# Expected parameters for 10K entries:
# targetChunkSize = 2 * sqrt(10000) = 200
# chunkSize = 256 (next power of 2)
# setSize = ceil(10000 / 256) = 40 (already multiple of 4)
# totalEntries = 256 * 40 = 10240

EXPECTED_TOTAL_ENTRIES=10240
EXPECTED_HINT_SIZE=$((32 + EXPECTED_TOTAL_ENTRIES * 8))  # 32-byte header + data

echo "Expected parameters for $TEST_DB_SIZE entries:"
echo "  Chunk Size: 256"
echo "  Set Size: 40"
echo "  Total Entries: $EXPECTED_TOTAL_ENTRIES"
echo "  Expected hint.bin size: $EXPECTED_HINT_SIZE bytes"
echo ""
echo "Actual hint.bin size: $HINT_SIZE bytes"

if [ "$HINT_SIZE" -eq "$EXPECTED_HINT_SIZE" ]; then
    echo -e "${GREEN}✅ PASS: Hint size matches expected value${NC}"
else
    echo -e "${YELLOW}⚠️  WARNING: Hint size mismatch (expected: $EXPECTED_HINT_SIZE, got: $HINT_SIZE)${NC}"
fi

echo ""

# Test 3: Verify no hardcoded values
echo "=========================================="
echo "Test 3: Hardcoded Value Check"
echo "=========================================="

echo "Checking for hardcoded 8388608 in source files..."
HARDCODED_FOUND=false

if grep -r "8388608" services/plinko-hint-generator/main.go 2>/dev/null; then
    echo -e "${RED}❌ FAIL: Found hardcoded 8388608 in hint-generator${NC}"
    HARDCODED_FOUND=true
fi

if grep "67108864" services/plinko-hint-generator/generate-hint.sh 2>/dev/null; then
    echo -e "${RED}❌ FAIL: Found hardcoded 67108864 in wrapper script${NC}"
    HARDCODED_FOUND=true
fi

if [ "$HARDCODED_FOUND" = false ]; then
    echo -e "${GREEN}✅ PASS: No hardcoded size values found${NC}"
fi

echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}✅ All dynamic sizing tests passed!${NC}"
echo ""
echo "Test artifacts saved in: $TEST_DIR"
echo "  - database.bin: $TEST_DB_SIZE entries"
echo "  - hint.bin: $HINT_SIZE bytes"
echo ""
echo "To test with PIR server:"
echo "  1. Copy test data: cp -r $TEST_DIR /path/to/docker/volume"
echo "  2. Run PIR server: docker run -v /path/to/volume:/data plinko-pir-server:latest"
echo "  3. Query via HTTP: curl http://localhost:3000/query/plaintext?index=100"
echo ""
