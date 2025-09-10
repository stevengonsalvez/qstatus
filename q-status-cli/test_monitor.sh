#!/bin/bash

# Test script to check Q-Status monitor startup

echo "Testing Q-Status Monitor startup..."

# Check if binary exists
if [ ! -f "./target/release/q-status" ]; then
    echo "Error: Binary not found at ./target/release/q-status"
    exit 1
fi

echo "Binary found: ./target/release/q-status"
echo "Binary size: $(ls -lh ./target/release/q-status | awk '{print $5}')"
echo ""

# Check version
echo "Version check:"
./target/release/q-status --version
echo ""

# Check help
echo "Help output:"
./target/release/q-status --help
echo ""

# Check if Q database exists
Q_DB="$HOME/Library/Application Support/amazon-q/data.sqlite3"
if [ -f "$Q_DB" ]; then
    echo "Q database found at: $Q_DB"
    echo "Database size: $(ls -lh "$Q_DB" | awk '{print $5}')"
else
    echo "Warning: Q database not found at expected location"
fi
echo ""

# Try to run with debug flag (will fail in non-TTY but show startup info)
echo "Attempting startup with debug mode (expecting TTY error):"
./target/release/q-status --debug 2>&1 | head -20 || true