#!/bin/sh
set -e

echo "Plinko PIR Hint Generator - Wrapper Script"
echo "=========================================="
echo ""

# Wait for database.bin to exist
echo "Checking for database.bin..."
while [ ! -f /data/database.bin ]; do
    echo "  Waiting for database.bin to be generated..."
    sleep 2
done

# Check database.bin size (dynamic - no hardcoded expectations)
DB_SIZE=$(stat -c%s /data/database.bin 2>/dev/null || stat -f%z /data/database.bin 2>/dev/null)
DB_SIZE_MB=$((DB_SIZE / 1024 / 1024))
DB_ENTRIES=$((DB_SIZE / 52))

echo "✅ database.bin found"
echo "  Size: $DB_SIZE bytes ($DB_SIZE_MB MB)"
echo "  Entries: $DB_ENTRIES"
echo ""

# Run hint generator (will auto-detect size from file)
echo "Starting hint generation..."
/app/hint-generator

echo ""
echo "Hint generation complete!"
