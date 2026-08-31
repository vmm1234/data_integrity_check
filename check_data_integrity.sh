#!/bin/bash
# ============================================================================
# Shell Script: Oracle Data Integrity Check (Two Database Support)
# ============================================================================
# This script compares tables across two different Oracle databases.
# It exports data from each database to CSV, then uses check_csv_integrity.sh
# to perform the comparison.
#
# USAGE:
#   ./check_data_integrity.sh <config_file> <SOURCE_SCHEMA> <SOURCE_TABLE> <TARGET_SCHEMA> <TARGET_TABLE> [SOURCE_PARTITION] [TARGET_PARTITION]
#
# EXAMPLES:
#   ./check_data_integrity.sh db_config.conf TEST USERS TEST USERS2
#   ./check_data_integrity.sh db_config.conf TEST USERS TEST USERS2 P_EAST P_EAST
# ============================================================================

set -e

# ============================================================================
# ARGUMENT VALIDATION
# ============================================================================
if [ $# -lt 5 ]; then
    echo "ERROR: At least 5 arguments required."
    echo "Usage: $0 <config_file> <SOURCE_SCHEMA> <SOURCE_TABLE> <TARGET_SCHEMA> <TARGET_TABLE> [SOURCE_PARTITION] [TARGET_PARTITION]"
    echo "Example: $0 db_config.conf TEST USERS TEST USERS2"
    echo "         $0 db_config.conf TEST USERS TEST USERS2 P_EAST P_EAST"
    exit 1
fi

CONFIG_FILE="$1"
SOURCE_SCHEMA="$2"
SOURCE_TABLE="$3"
TARGET_SCHEMA="$4"
TARGET_TABLE="$5"
SOURCE_PARTITION="${6:-}"
TARGET_PARTITION="${7:-}"

# ============================================================================
# LOAD CONFIGURATION
# ============================================================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file '$CONFIG_FILE' not found."
    exit 1
fi

# Source the configuration file
. "$CONFIG_FILE"

# Validate required configuration
if [ -z "$SOURCE_DB_USER" ] || [ -z "$SOURCE_DB_PASSWORD" ] || [ -z "$SOURCE_DB_HOST" ] || [ -z "$SOURCE_DB_PORT" ] || [ -z "$SOURCE_DB_SERVICE" ]; then
    echo "ERROR: Source database configuration incomplete in $CONFIG_FILE"
    exit 1
fi

if [ -z "$TARGET_DB_USER" ] || [ -z "$TARGET_DB_PASSWORD" ] || [ -z "$TARGET_DB_HOST" ] || [ -z "$TARGET_DB_PORT" ] || [ -z "$TARGET_DB_SERVICE" ]; then
    echo "ERROR: Target database configuration incomplete in $CONFIG_FILE"
    exit 1
fi

# Build connection strings
SOURCE_CONN="${SOURCE_DB_USER}/${SOURCE_DB_PASSWORD}@${SOURCE_DB_HOST}:${SOURCE_DB_PORT}/${SOURCE_DB_SERVICE}"
TARGET_CONN="${TARGET_DB_USER}/${TARGET_DB_PASSWORD}@${TARGET_DB_HOST}:${TARGET_DB_PORT}/${TARGET_DB_SERVICE}"

# ============================================================================
# CLI TOOL DETECTION (sqlplus or sqlcl)
# ============================================================================
# Determine which CLI tool to use
if [ -n "$DB_CLI_TOOL" ]; then
    # User specified a preference
    if [ "$DB_CLI_TOOL" = "sqlplus" ]; then
        SQL_CLI="${SQLPLUS_PATH:-sqlplus}"
        SQL_CLI_NAME="sqlplus"
    elif [ "$DB_CLI_TOOL" = "sqlcl" ]; then
        SQL_CLI="${SQLCL_PATH:-sql}"
        SQL_CLI_NAME="sqlcl"
    else
        echo "WARNING: Unknown DB_CLI_TOOL '$DB_CLI_TOOL', auto-detecting..."
        SQL_CLI=""
        SQL_CLI_NAME=""
    fi
fi

# Auto-detect if not set
if [ -z "$SQL_CLI" ]; then
    if command -v "${SQLPLUS_PATH:-sqlplus}" &> /dev/null; then
        SQL_CLI="${SQLPLUS_PATH:-sqlplus}"
        SQL_CLI_NAME="sqlplus"
    elif command -v "${SQLCL_PATH:-sql}" &> /dev/null; then
        SQL_CLI="${SQLCL_PATH:-sql}"
        SQL_CLI_NAME="sqlcl"
    fi
fi

# Final validation
if [ -z "$SQL_CLI" ]; then
    echo "ERROR: Neither sqlplus nor sqlcl found."
    echo "  - sqlplus: Set SQLPLUS_PATH in $CONFIG_FILE or add to PATH"
    echo "  - sqlcl:   Set SQLCL_PATH in $CONFIG_FILE or add to PATH"
    echo "  - Or set DB_CLI_TOOL to 'sqlplus' or 'sqlcl' explicitly"
    exit 1
fi

echo "Using CLI tool: $SQL_CLI_NAME ($SQL_CLI)"

# ============================================================================
# PATHS AND TEMP FILES
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXPORT_SQL="${SCRIPT_DIR}/export_table_to_csv.sql"
CSV_CHECKER="${SCRIPT_DIR}/check_csv_integrity.sh"

# Create temp directory for CSV files
TEMP_DIR=$(mktemp -d)
SOURCE_CSV="${TEMP_DIR}/source.csv"
TARGET_CSV="${TEMP_DIR}/target.csv"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Check if export SQL script exists
if [ ! -f "$EXPORT_SQL" ]; then
    echo "ERROR: Export SQL script not found at $EXPORT_SQL"
    exit 1
fi

# Check if CSV checker exists
if [ ! -f "$CSV_CHECKER" ]; then
    echo "ERROR: CSV integrity checker not found at $CSV_CHECKER"
    exit 1
fi

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================
export_table_to_csv() {
    local conn="$1"
    local schema="$2"
    local table="$3"
    local partition="${4:-NO_PARTITION}"
    local output_file="$5"

    echo "Exporting ${schema}.${table} to CSV..."

    "$SQL_CLI" -s "$conn" @"$EXPORT_SQL" "$schema" "$table" "$partition" > "$output_file" 2>&1

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to export ${schema}.${table}"
        cat "$output_file"
        return 1
    fi

    # Check for errors in output
    if grep -q "^ERROR:" "$output_file"; then
        echo "ERROR: Export failed for ${schema}.${table}"
        cat "$output_file"
        return 1
    fi

    local row_count=$(tail -n +2 "$output_file" | wc -l | tr -d ' ')
    echo "  Exported $row_count rows to $output_file"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
echo "============================================================================"
echo "DATA INTEGRITY CHECK (Two Database Mode)"
echo "============================================================================"
echo "Source: ${SOURCE_SCHEMA}.${SOURCE_TABLE} @ ${SOURCE_DB_HOST}:${SOURCE_DB_PORT}/${SOURCE_DB_SERVICE}"
echo "Target: ${TARGET_SCHEMA}.${TARGET_TABLE} @ ${TARGET_DB_HOST}:${TARGET_DB_PORT}/${TARGET_DB_SERVICE}"
if [ -n "$SOURCE_PARTITION" ]; then
    echo "Source Partition: $SOURCE_PARTITION"
fi
if [ -n "$TARGET_PARTITION" ]; then
    echo "Target Partition: $TARGET_PARTITION"
fi
echo "============================================================================"
echo ""

# Export source table
export_table_to_csv "$SOURCE_CONN" "$SOURCE_SCHEMA" "$SOURCE_TABLE" "$SOURCE_PARTITION" "$SOURCE_CSV"
if [ $? -ne 0 ]; then
    echo "ERROR: Source export failed. Aborting."
    exit 1
fi

echo ""

# Export target table
export_table_to_csv "$TARGET_CONN" "$TARGET_SCHEMA" "$TARGET_TABLE" "$TARGET_PARTITION" "$TARGET_CSV"
if [ $? -ne 0 ]; then
    echo "ERROR: Target export failed. Aborting."
    exit 1
fi

echo ""
echo "============================================================================"
echo "COMPARING SOURCE AND TARGET DATA"
echo "============================================================================"
echo ""

# Run CSV integrity check
"$CSV_CHECKER" "$SOURCE_CSV" "$TARGET_CSV"

echo ""
echo "============================================================================"
echo "TEMPORARY FILES"
echo "============================================================================"
echo "Source CSV: $SOURCE_CSV"
echo "Target CSV: $TARGET_CSV"
echo "(These files will be cleaned up on script exit)"