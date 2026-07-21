#!/bin/bash
# ============================================================================
# SCRIPT test case: Validate project environment
# Checks that key directories and config files exist.
# Exit 0 = PASS, non-zero = FAIL
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Environment Validation ==="
echo "Project dir: $PROJECT_DIR"
echo ""

ERRORS=0

# Check logs directory
if [ -d "${PROJECT_DIR}/logs" ]; then
    echo "[PASS] logs/ directory exists"
else
    echo "[FAIL] logs/ directory not found"
    ERRORS=$((ERRORS + 1))
fi

# Check config file
if [ -f "${PROJECT_DIR}/config/test_config.csv" ]; then
    echo "[PASS] config/test_config.csv exists"
else
    echo "[FAIL] config/test_config.csv not found"
    ERRORS=$((ERRORS + 1))
fi

# Check CSV test data
if [ -f "${PROJECT_DIR}/test_csv/source.csv" ]; then
    echo "[PASS] test_csv/source.csv exists"
else
    echo "[FAIL] test_csv/source.csv not found"
    ERRORS=$((ERRORS + 1))
fi

# Check check_csv_integrity.sh is executable
if [ -x "${PROJECT_DIR}/check_csv_integrity.sh" ]; then
    echo "[PASS] check_csv_integrity.sh is executable"
else
    echo "[FAIL] check_csv_integrity.sh not found or not executable"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=== Validation complete: $ERRORS error(s) ==="

if [ $ERRORS -gt 0 ]; then
    exit 1
fi
exit 0
