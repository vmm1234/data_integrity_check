#!/bin/bash
# ============================================================================
# Pre-test script: sample test case setup
# 1. Copy test_input/test01.csv to project root as source.csv
# 2. Run test_script2.sh (generates target.csv from source.csv)
# 3. Exit 0 if both steps succeed, non-zero on failure
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "[test1] Starting pre-test setup..."

# Step 1: Copy input file to execution folder (project root)
INPUT_FILE="${PROJECT_DIR}/test_input/test01.csv"
SOURCE_FILE="${PROJECT_DIR}/source.csv"

if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found: $INPUT_FILE"
    exit 1
fi

cp "$INPUT_FILE" "$SOURCE_FILE"
echo "[test1] Copied test01.csv -> source.csv"

# Step 2: Run test_script2.sh
echo "[test1] Running test_script2.sh..."
"${SCRIPT_DIR}/test_script2.sh"
RC=$?

if [ $RC -ne 0 ]; then
    echo "ERROR: test_script2.sh failed with exit code $RC"
    exit $RC
fi

# Step 3: Verify results (both source.csv and target.csv exist)
echo "[test1] Verifying results..."
if [ ! -f "${PROJECT_DIR}/source.csv" ] || [ ! -f "${PROJECT_DIR}/target.csv" ]; then
    echo "ERROR: source.csv or target.csv missing after setup"
    exit 1
fi

echo "[test1] Pre-test setup complete -- source.csv and target.csv ready"
exit 0
