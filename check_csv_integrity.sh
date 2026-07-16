#!/bin/bash
# ============================================================================
# Shell Script: CSV Data Integrity Check
# ============================================================================
# This script compares two CSV files for data integrity.
# It handles files with headers and automatically discovers columns.
#
# USAGE:
#   ./check_csv_integrity.sh <source_csv> <target_csv>
#
# EXAMPLE:
#   ./check_csv_integrity.sh source.csv target.csv
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# ARGUMENT VALIDATION
# ============================================================================
if [ $# -ne 2 ]; then
    echo "ERROR: Exactly 2 arguments required."
    echo "Usage: $0 <source_csv> <target_csv>"
    exit 1
fi

SOURCE_FILE="$1"
TARGET_FILE="$2"

# Check if files exist
if [ ! -f "$SOURCE_FILE" ]; then
    echo "ERROR: Source file '$SOURCE_FILE' not found."
    exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
    echo "ERROR: Target file '$TARGET_FILE' not found."
    exit 1
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Get column names from CSV header
get_columns() {
    local file="$1"
    head -n 1 "$file" | tr ',' '\n'
}

# Get column count from CSV header
get_column_count() {
    local file="$1"
    head -n 1 "$file" | awk -F',' '{print NF}'
}

# Normalize CSV row (trim whitespace, handle empty values)
normalize_row() {
    awk -F',' '{
        for(i=1; i<=NF; i++) {
            gsub(/^[ \t]+|[ \t]+$/, "", $i)
            if ($i == "") $i = "NULL"
            printf "%s", $i
            if (i < NF) printf ","
        }
        print ""
    }'
}

# ============================================================================
# MAIN COMPARISON LOGIC
# ============================================================================

echo "============================================================================"
echo "CSV DATA INTEGRITY CHECK"
echo "============================================================================"
echo "Source File: $SOURCE_FILE"
echo "Target File: $TARGET_FILE"
echo "Report Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================================"
echo ""

# Get column information
SOURCE_COLUMNS=$(get_columns "$SOURCE_FILE")
TARGET_COLUMNS=$(get_columns "$TARGET_FILE")
SOURCE_COL_COUNT=$(get_column_count "$SOURCE_FILE")
TARGET_COL_COUNT=$(get_column_count "$TARGET_FILE")

echo "Source Columns: $SOURCE_COLUMNS"
echo "Target Columns: $TARGET_COLUMNS"
echo ""

# Check if column counts match
if [ "$SOURCE_COL_COUNT" -ne "$TARGET_COL_COUNT" ]; then
    echo -e "${RED}WARNING: Column count mismatch!${NC}"
    echo "Source has $SOURCE_COL_COUNT columns, Target has $TARGET_COL_COUNT columns"
    echo ""
fi

# Check if column names match
if [ "$SOURCE_COLUMNS" != "$TARGET_COLUMNS" ]; then
    echo -e "${RED}WARNING: Column names mismatch!${NC}"
    echo "Source: $SOURCE_COLUMNS"
    echo "Target: $TARGET_COLUMNS"
    echo ""
fi

# ============================================================================
# ROW COUNT SUMMARY
# ============================================================================
echo "ROW COUNT SUMMARY"
echo "-----------------"

SOURCE_DATA_ROWS=$(tail -n +2 "$SOURCE_FILE" | wc -l | tr -d ' ')
TARGET_DATA_ROWS=$(tail -n +2 "$TARGET_FILE" | wc -l | tr -d ' ')

echo "Source Data Rows:      $SOURCE_DATA_ROWS"
echo "Target Data Rows:      $TARGET_DATA_ROWS"
echo ""

# ============================================================================
# DATA MATCH SUMMARY
# ============================================================================
echo "DATA MATCH SUMMARY"
echo "------------------"

# Create normalized temporary files for comparison
SOURCE_NORMALIZED=$(mktemp)
TARGET_NORMALIZED=$(mktemp)
trap "rm -f $SOURCE_NORMALIZED $TARGET_NORMALIZED" EXIT

# Normalize and sort data (skip header)
tail -n +2 "$SOURCE_FILE" | normalize_row | sort > "$SOURCE_NORMALIZED"
tail -n +2 "$TARGET_FILE" | normalize_row | sort > "$TARGET_NORMALIZED"

# Rows only in source
SOURCE_ONLY=$(comm -23 "$SOURCE_NORMALIZED" "$TARGET_NORMALIZED" | wc -l | tr -d ' ')
echo -e "Rows in Source Only:   $SOURCE_ONLY"

# Rows only in target
TARGET_ONLY=$(comm -13 "$SOURCE_NORMALIZED" "$TARGET_NORMALIZED" | wc -l | tr -d ' ')
echo -e "Rows in Target Only:   $TARGET_ONLY"

# Matching rows (intersection)
MATCHING=$(comm -12 "$SOURCE_NORMALIZED" "$TARGET_NORMALIZED" | wc -l | tr -d ' ')
echo -e "Matching Rows:         $MATCHING"

# Mismatched rows
MISMATCHED=$((SOURCE_ONLY + TARGET_ONLY))
echo -e "Mismatched Rows:       $MISMATCHED"
echo ""

# ============================================================================
# DETAILED MISMATCH REPORT
# ============================================================================
echo "============================================================================"
echo "DETAILED MISMATCH REPORT"
echo "============================================================================"
echo ""

echo "Rows Only in SOURCE (up to 100):"
echo "----------------------------------------"
comm -23 "$SOURCE_NORMALIZED" "$TARGET_NORMALIZED" | head -n 100 | while IFS= read -r line; do
    echo "$line"
done
echo ""

echo "Rows Only in TARGET (up to 100):"
echo "----------------------------------------"
comm -13 "$SOURCE_NORMALIZED" "$TARGET_NORMALIZED" | head -n 100 | while IFS= read -r line; do
    echo "$line"
done
echo ""

# ============================================================================
# COLUMN-BY-COLUMN MISMATCH DETAILS
# ============================================================================
echo "============================================================================"
echo "COLUMN-BY-COLUMN MISMATCH DETAILS"
echo "============================================================================"
echo "Note: This section shows up to 100 mismatched row comparisons"
echo ""

# Get column names as array
IFS=',' read -r -a COL_NAMES <<< "$SOURCE_COLUMNS"
NUM_COLS=${#COL_NAMES[@]}

# Print header
HEADER="SOURCE_ROW"
for i in $(seq 0 $((NUM_COLS - 1))); do
    HEADER="$HEADER | ${COL_NAMES[$i]}_SRC | ${COL_NAMES[$i]}_TGT"
done
echo "$HEADER"
echo "$(printf '%0.s-' $(seq 1 ${#HEADER}))"

# Compare rows column by column
# Create a combined comparison file
COMPARISON_FILE=$(mktemp)
trap "rm -f $SOURCE_NORMALIZED $TARGET_NORMALIZED $COMPARISON_FILE" EXIT

# Use awk to compare rows and show differences
awk -F',' -v num_cols="$NUM_COLS" '
BEGIN {
    row_num = 0
}
NR == FNR {
    # Reading source file
    source_rows[NR] = $0
    for (i = 1; i <= NF; i++) {
        source_data[NR, i] = $i
    }
    source_count = NR
    next
}
{
    # Reading target file
    target_row_num = FNR
    target_data[FNR, 1] = $0
    for (i = 1; i <= NF; i++) {
        target_data[FNR, i] = $i
    }
    target_count = FNR
}
END {
    # Compare all rows
    max_rows = (source_count > target_count) ? source_count : target_count
    
    for (r = 1; r <= max_rows && row_num < 100; r++) {
        row_num++
        
        # Check if row exists in both
        if (r > source_count) {
            # Only in target
            printf "%d |", r
            for (i = 1; i <= num_cols; i++) {
                printf " NULL | %s", target_data[r, i]
            }
            printf " | TARGET_ONLY\n"
        } else if (r > target_count) {
            # Only in source
            printf "%d |", r
            for (i = 1; i <= num_cols; i++) {
                printf " %s | NULL", source_data[r, i]
            }
            printf " | SOURCE_ONLY\n"
        } else {
            # Compare columns
            is_match = 1
            printf "%d |", r
            for (i = 1; i <= num_cols; i++) {
                printf " %s | %s", source_data[r, i], target_data[r, i]
                if (source_data[r, i] != target_data[r, i]) {
                    is_match = 0
                }
            }
            if (is_match) {
                printf " | MATCH\n"
            } else {
                printf " | MISMATCH\n"
            }
        }
    }
}
' "$SOURCE_NORMALIZED" "$TARGET_NORMALIZED" | head -n 100

echo ""
echo "============================================================================"
echo "END OF CSV DATA INTEGRITY CHECK REPORT"
echo "============================================================================"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "============================================================================"
echo "SUMMARY"
echo "============================================================================"

if [ "$MISMATCHED" -eq 0 ]; then
    echo -e "${GREEN}RESULT: All data matches!${NC}"
    echo "Source and target files are identical."
else
    echo -e "${RED}RESULT: Data integrity check found $MISMATCHED mismatched row(s)${NC}"
    echo "  - Rows only in source: $SOURCE_ONLY"
    echo "  - Rows only in target: $TARGET_ONLY"
    echo "  - Matching rows: $MATCHING"
fi

echo "============================================================================"