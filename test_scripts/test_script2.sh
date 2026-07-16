#!/bin/bash
# ============================================================================
# Helper script: generate target.csv from source.csv
# Copies source.csv to target.csv (simulates a data pipeline step).
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE="${PROJECT_DIR}/source.csv"
TARGET="${PROJECT_DIR}/target.csv"

if [ ! -f "$SOURCE" ]; then
    echo "ERROR: source.csv not found at $SOURCE"
    exit 1
fi

cp "$SOURCE" "$TARGET"
echo "Generated target.csv from source.csv"
