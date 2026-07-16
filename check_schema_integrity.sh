#!/bin/bash
# ============================================================================
# Shell Script: Oracle Schema Integrity Check (Cross-Database)
# ============================================================================
# Compares all schema objects (TABLES, VIEWS, PROCEDURES, FUNCTIONS, PACKAGES,
# TRIGGERS, SEQUENCES, INDEXES, SYNONYMS, MATERIALIZED VIEWS) between two
# schemas on different Oracle databases.
#
# USAGE:
#   ./check_schema_integrity.sh <config_file> <SOURCE_SCHEMA> <TARGET_SCHEMA>
#
# EXAMPLE:
#   ./check_schema_integrity.sh db_config.conf HR_PROD HR_STAGING
#
# The config file must define DB connection variables for both databases.
# See db_config.conf for the expected format.
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# ARGUMENT VALIDATION
# ============================================================================
if [ $# -ne 3 ]; then
    echo "ERROR: Exactly 3 arguments required."
    echo "Usage: $0 <config_file> <SOURCE_SCHEMA> <TARGET_SCHEMA>"
    echo "Example: $0 db_config.conf HR_PROD HR_STAGING"
    exit 1
fi

CONFIG_FILE="$1"
SOURCE_SCHEMA="$2"
TARGET_SCHEMA="$3"

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
if [ -n "$DB_CLI_TOOL" ]; then
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

if [ -z "$SQL_CLI" ]; then
    if command -v "${SQLPLUS_PATH:-sqlplus}" &> /dev/null; then
        SQL_CLI="${SQLPLUS_PATH:-sqlplus}"
        SQL_CLI_NAME="sqlplus"
    elif command -v "${SQLCL_PATH:-sql}" &> /dev/null; then
        SQL_CLI="${SQLCL_PATH:-sql}"
        SQL_CLI_NAME="sqlcl"
    fi
fi

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
EXPORT_SQL="${SCRIPT_DIR}/export_schema_objects.sql"

# Check export script exists
if [ ! -f "$EXPORT_SQL" ]; then
    echo "ERROR: Export SQL script not found at $EXPORT_SQL"
    exit 1
fi

# Create temp directory for export files
TEMP_DIR=$(mktemp -d)
SOURCE_FILE="${TEMP_DIR}/source_schema.txt"
TARGET_FILE="${TEMP_DIR}/target_schema.txt"
SOURCE_ONLY_FILE="${TEMP_DIR}/source_only.txt"
TARGET_ONLY_FILE="${TEMP_DIR}/target_only.txt"
MATCHING_FILE="${TEMP_DIR}/matching.txt"

# INVALID object tracking files
SOURCE_INVALID_FILE="${TEMP_DIR}/source_invalid.txt"
TARGET_INVALID_FILE="${TEMP_DIR}/target_invalid.txt"
SRC_ONLY_INVALID="${TEMP_DIR}/src_only_invalid.txt"
TGT_ONLY_INVALID="${TEMP_DIR}/tgt_only_invalid.txt"
BOTH_INVALID="${TEMP_DIR}/both_invalid.txt"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# ============================================================================
# EXPORT FUNCTION
# ============================================================================
export_schema_objects() {
    local conn="$1"
    local schema="$2"
    local label="$3"
    local output_file="$4"
    local invalid_file="$5"

    echo "Connecting to ${label} database..."
    echo "  Exporting objects from schema: ${schema}"

    "$SQL_CLI" -s "$conn" @"$EXPORT_SQL" "$schema" > "$output_file" 2>&1

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to export objects from ${label} schema ${schema}"
        cat "$output_file"
        return 1
    fi

    # Check for SQL errors in output
    if grep -q "^ERROR:" "$output_file"; then
        echo "ERROR: Export failed for ${label} schema ${schema}"
        cat "$output_file"
        return 1
    fi

    # Separate INVALID lines from the main comparison output
    grep "^INVALID|" "$output_file" > "$invalid_file" 2>/dev/null || true
    grep -v "^INVALID|" "$output_file" > "${output_file}.tmp" && mv "${output_file}.tmp" "$output_file"

    # Sort the main output for comm-based comparison
    sort -o "$output_file" "$output_file"

    local obj_count=$(wc -l < "$output_file" | tr -d ' ')
    local inv_count=$(wc -l < "$invalid_file" | tr -d ' ')
    echo "  Exported ${obj_count} object fingerprint lines"
    if [ "$inv_count" -gt 0 ]; then
        echo "  WARNING: ${inv_count} object(s) with compilation errors (INVALID status)"
    fi
}

# ============================================================================
# HEADER
# ============================================================================
echo ""
echo "============================================================================"
echo "SCHEMA INTEGRITY CHECK"
echo "============================================================================"
echo "Source Schema: ${SOURCE_SCHEMA} @ ${SOURCE_DB_HOST}:${SOURCE_DB_PORT}/${SOURCE_DB_SERVICE}"
echo "Target Schema: ${TARGET_SCHEMA} @ ${TARGET_DB_HOST}:${TARGET_DB_PORT}/${TARGET_DB_SERVICE}"
echo "Objects Checked: TABLES (columns + constraints), VIEWS, PROCEDURES,"
echo "                 FUNCTIONS, PACKAGES, TYPES, TRIGGERS, SEQUENCES,"
echo "                 INDEXES, SYNONYMS, MATERIALIZED VIEWS,"
echo "                 DIRECTORIES, GRANTS (object/role/system), PARAMETERS"
echo "Report Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================================"
echo ""

# ============================================================================
# EXPORT SOURCE AND TARGET
# ============================================================================

export_schema_objects "$SOURCE_CONN" "$SOURCE_SCHEMA" "source" "$SOURCE_FILE" "$SOURCE_INVALID_FILE"
if [ $? -ne 0 ]; then
    echo "ERROR: Source schema export failed. Aborting."
    exit 1
fi

echo ""

export_schema_objects "$TARGET_CONN" "$TARGET_SCHEMA" "target" "$TARGET_FILE" "$TARGET_INVALID_FILE"
if [ $? -ne 0 ]; then
    echo "ERROR: Target schema export failed. Aborting."
    exit 1
fi

echo ""

# ============================================================================
# COMPARISON
# ============================================================================
echo "============================================================================"
echo "COMPARING SCHEMA OBJECTS"
echo "============================================================================"
echo ""

# Use comm for set-based comparison
comm -23 "$SOURCE_FILE" "$TARGET_FILE" > "$SOURCE_ONLY_FILE"
comm -13 "$SOURCE_FILE" "$TARGET_FILE" > "$TARGET_ONLY_FILE"
comm -12 "$SOURCE_FILE" "$TARGET_FILE" > "$MATCHING_FILE"

SOURCE_ONLY=$(wc -l < "$SOURCE_ONLY_FILE" | tr -d ' ')
TARGET_ONLY=$(wc -l < "$TARGET_ONLY_FILE" | tr -d ' ')
MATCHING=$(wc -l < "$MATCHING_FILE" | tr -d ' ')
MISMATCHED=$((SOURCE_ONLY + TARGET_ONLY))

# ============================================================================
# ROW COUNT SUMMARY
# ============================================================================
echo "FINGERPRINT LINE SUMMARY"
echo "------------------------"
echo -e "Source Fingerprint Lines:     $(wc -l < "$SOURCE_FILE" | tr -d ' ')"
echo -e "Target Fingerprint Lines:     $(wc -l < "$TARGET_FILE" | tr -d ' ')"
echo ""
echo -e "Matching Lines:               ${MATCHING}"
echo -e "Source-Only Lines:            ${SOURCE_ONLY}"
echo -e "Target-Only Lines:            ${TARGET_ONLY}"
echo -e "Mismatched Lines:             ${MISMATCHED}"
echo ""

# ============================================================================
# BREAKDOWN BY OBJECT TYPE
# ============================================================================
echo "============================================================================"
echo "BREAKDOWN BY OBJECT TYPE"
echo "============================================================================"
echo ""

# Type definitions (parallel arrays, compatible with bash 3.2)
TYPE_PREFIXES=(TAB_COL CONSTR VIEW SRC TRIG SEQ IDX SYN MVIEW DIR GRANT_OBJ GRANT_ROLE GRANT_SYS PARAM)
TYPE_LABELS=("Table Columns" "Constraints" "Views" "Source Code (Proc/Func/Pkg/Type)" "Triggers" "Sequences" "Indexes" "Synonyms" "Materialized Views" "Directories" "Object Grants" "Role Grants" "System Privileges" "Parameters")

get_label() {
    local p="$1"
    for i in "${!TYPE_PREFIXES[@]}"; do
        if [ "${TYPE_PREFIXES[$i]}" = "$p" ]; then
            echo "${TYPE_LABELS[$i]}"
            return
        fi
    done
    echo "$p"
}

printf "%-10s %-35s %10s %10s %10s\n" "Type" "Description" "SrcOnly" "TgtOnly" "Match"
printf "%-10s %-35s %10s %10s %10s\n" "----------" "-----------------------------------" "-------" "-------" "------"

HAS_ANY=false
for prefix in "${TYPE_PREFIXES[@]}"; do
    s=$(grep -c "^${prefix}|" "$SOURCE_ONLY_FILE" 2>/dev/null || true)
    t=$(grep -c "^${prefix}|" "$TARGET_ONLY_FILE" 2>/dev/null || true)
    m=$(grep -c "^${prefix}|" "$MATCHING_FILE" 2>/dev/null || true)
    total=$((s + t + m))
    if [ "$total" -gt 0 ]; then
        HAS_ANY=true
        label=$(get_label "$prefix")
        printf "%-10s %-35s %10s %10s %10s\n" "$prefix" "$label" "$s" "$t" "$m"
    fi
done

if [ "$HAS_ANY" = false ]; then
    echo "(No objects found in either schema)"
fi
echo ""

# ============================================================================
# DETAILED DIFFERENCES
# ============================================================================
echo "============================================================================"
echo "DETAILED DIFFERENCES"
echo "============================================================================"
echo ""

if [ "$MISMATCHED" -gt 0 ]; then
    # Helper to print detailed diff grouped by type
    print_diff_grouped() {
        local file="$1"
        local prefix_char="$2"
        local title="$3"
        echo -e "${YELLOW}${title}${NC}"
        echo "--------------------------------------------------------"
        local any=false
        for prefix in "${TYPE_PREFIXES[@]}"; do
            count=$(grep -c "^${prefix}|" "$file" 2>/dev/null || true)
            if [ "$count" -gt 0 ]; then
                any=true
                label=$(get_label "$prefix")
                echo ""
                echo "[${prefix} - ${label}] (${count} line(s))"
                grep "^${prefix}|" "$file" | head -50 | while IFS= read -r line; do
                    echo "  ${prefix_char} $line"
                done
                if [ "$count" -gt 50 ]; then
                    echo "  ... and $((count - 50)) more line(s)"
                fi
            fi
        done
        if [ "$any" = false ]; then
            echo "  (none)"
        fi
    }

    # Group and show source-only differences by type
    print_diff_grouped "$SOURCE_ONLY_FILE" "<" "Differences - Objects/attributes only in SOURCE schema:"

    echo ""

    # Group and show target-only differences by type
    print_diff_grouped "$TARGET_ONLY_FILE" ">" "Differences - Objects/attributes only in TARGET schema:"
else
    echo -e "${GREEN}All schema objects match!${NC}"
fi

echo ""

# ============================================================================
# COMPILATION STATUS CHECK
# ============================================================================
echo "============================================================================"
echo "COMPILATION STATUS CHECK"
echo "============================================================================"
echo ""

HAS_TGT_ONLY_INVALID=false
SRC_INV_COUNT=$(wc -l < "$SOURCE_INVALID_FILE" 2>/dev/null | tr -d ' ')
TGT_INV_COUNT=$(wc -l < "$TARGET_INVALID_FILE" 2>/dev/null | tr -d ' ')

# Normalize INVALID lines: strip owner, compare by object_type|object_name
grep "^INVALID|" "$SOURCE_INVALID_FILE" 2>/dev/null | awk -F'|' '{print $3"|"$4}' | sort > "${TEMP_DIR}/_src_inv_keys" || true
grep "^INVALID|" "$TARGET_INVALID_FILE" 2>/dev/null | awk -F'|' '{print $3"|"$4}' | sort > "${TEMP_DIR}/_tgt_inv_keys" || true

comm -23 "${TEMP_DIR}/_src_inv_keys" "${TEMP_DIR}/_tgt_inv_keys" > "$SRC_ONLY_INVALID" 2>/dev/null
comm -13 "${TEMP_DIR}/_src_inv_keys" "${TEMP_DIR}/_tgt_inv_keys" > "$TGT_ONLY_INVALID" 2>/dev/null
comm -12 "${TEMP_DIR}/_src_inv_keys" "${TEMP_DIR}/_tgt_inv_keys" > "$BOTH_INVALID" 2>/dev/null

SRC_ONLY_INV_COUNT=$(wc -l < "$SRC_ONLY_INVALID" | tr -d ' ')
TGT_ONLY_INV_COUNT=$(wc -l < "$TGT_ONLY_INVALID" | tr -d ' ')
BOTH_INV_COUNT=$(wc -l < "$BOTH_INVALID" | tr -d ' ')

if [ "$SRC_ONLY_INV_COUNT" -gt 0 ] || [ "$TGT_ONLY_INV_COUNT" -gt 0 ] || [ "$BOTH_INV_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}Invalid (non-compiled) objects detected:${NC}"
    echo ""

    if [ "$SRC_ONLY_INV_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}WARNING: Objects invalid in SOURCE but valid in TARGET:${NC}"
        echo "  (source has compilation issues not present in target)"
        while IFS= read -r obj; do
            echo "  - $obj"
        done < "$SRC_ONLY_INVALID"
        echo ""
    fi

    if [ "$TGT_ONLY_INV_COUNT" -gt 0 ]; then
        HAS_TGT_ONLY_INVALID=true
        echo -e "${RED}FAIL: Objects valid in SOURCE but invalid in TARGET:${NC}"
        echo "  (source compiles, target does not - regression detected!)"
        while IFS= read -r obj; do
            echo "  - $obj"
        done < "$TGT_ONLY_INVALID"
        echo ""
    fi

    if [ "$BOTH_INV_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}WARNING: Objects invalid in BOTH schemas:${NC}"
        echo "  (same issue exists in source and target)"
        while IFS= read -r obj; do
            echo "  - $obj"
        done < "$BOTH_INVALID"
        echo ""
    fi
else
    echo -e "${GREEN}All compiled objects are in VALID status.${NC}"
    echo ""
fi

# ============================================================================
# SUGGESTED OBJECT-LEVEL SUMMARY
# ============================================================================
echo "============================================================================"
echo "OBJECT-LEVEL DIFFERENCE SUMMARY"
echo "============================================================================"
echo ""

# Extract unique object names from source-only lines
list_source_objects() {
    local file="$1"
    local any=false
    for prefix in "${TYPE_PREFIXES[@]}"; do
        count=$(grep -c "^${prefix}|" "$file" 2>/dev/null || true)
        [ "$count" -eq 0 ] && continue
        any=true
        label=$(get_label "$prefix")
        echo "  ${label}:"
        if [ "$prefix" = "TAB_COL" ] || [ "$prefix" = "CONSTR" ]; then
            # owner|table|col|... -> field 3 = table name
            grep "^${prefix}|" "$file" | awk -F'|' '!seen[$3]++ {print "    - " $3}' | head -20
        elif [ "$prefix" = "SRC" ]; then
            # SRC: owner|type|name|line|text -> field 4 = object name
            grep "^${prefix}|" "$file" | awk -F'|' '!seen[$4]++ {print "    - " $4}' | head -20
        else
            # VIEW, TRIG, SEQ, IDX, SYN, MVIEW: prefix|owner|name|...
            grep "^${prefix}|" "$file" | awk -F'|' '!seen[$3]++ {print "    - " $3}' | head -20
        fi
    done
    if [ "$any" = false ]; then
        echo "  (none)"
    fi
}

echo -e "${CYAN}Objects/attributes only in SOURCE schema:${NC}"
list_source_objects "$SOURCE_ONLY_FILE"
echo ""
echo -e "${CYAN}Objects/attributes only in TARGET schema:${NC}"
list_source_objects "$TARGET_ONLY_FILE"

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo "============================================================================"
echo "SUMMARY"
echo "============================================================================"

# Determine overall result
OVERALL_FAIL=false
FAIL_REASON=""

if [ "$MISMATCHED" -gt 0 ]; then
    OVERALL_FAIL=true
    FAIL_REASON="Schema comparison found differences"
fi

if [ "$HAS_TGT_ONLY_INVALID" = true ]; then
    OVERALL_FAIL=true
    if [ -n "$FAIL_REASON" ]; then
        FAIL_REASON="${FAIL_REASON}; Target has invalid objects while source objects are valid"
    else
        FAIL_REASON="Target has invalid objects while source objects are valid"
    fi
fi

if [ "$OVERALL_FAIL" = false ]; then
    echo -e "${GREEN}RESULT: PASS - All schema objects match and are valid!${NC}"
    echo "Source and target schemas are structurally identical with no compilation issues."
else
    echo -e "${RED}RESULT: FAIL - ${FAIL_REASON}${NC}"
    echo "  - Source-only fingerprint lines:  $SOURCE_ONLY"
    echo "  - Target-only fingerprint lines:  $TARGET_ONLY"
    echo "  - Matching fingerprint lines:     $MATCHING"
    SRC_INV_COUNT=$(wc -l < "$SOURCE_INVALID_FILE" 2>/dev/null | tr -d ' ')
    TGT_INV_COUNT=$(wc -l < "$TARGET_INVALID_FILE" 2>/dev/null | tr -d ' ')
    if [ "$SRC_INV_COUNT" -gt 0 ] || [ "$TGT_INV_COUNT" -gt 0 ]; then
        echo "  - Source INVALID objects:         $SRC_INV_COUNT"
        echo "  - Target INVALID objects:         $TGT_INV_COUNT"
    fi
fi

echo "============================================================================"

# Save report
REPORT_FILE="${SCRIPT_DIR}/data_integrity_report.txt"
{
    echo "============================================================================"
    echo "SCHEMA INTEGRITY CHECK REPORT"
    echo "============================================================================"
    echo "Source Schema: ${SOURCE_SCHEMA} @ ${SOURCE_DB_HOST}:${SOURCE_DB_PORT}/${SOURCE_DB_SERVICE}"
    echo "Target Schema: ${TARGET_SCHEMA} @ ${TARGET_DB_HOST}:${TARGET_DB_PORT}/${TARGET_DB_SERVICE}"
    echo "Report Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "============================================================================"
    echo ""
    echo "FINGERPRINT LINE SUMMARY"
    echo "------------------------"
    echo "Source Fingerprint Lines:     $(wc -l < "$SOURCE_FILE" | tr -d ' ')"
    echo "Target Fingerprint Lines:     $(wc -l < "$TARGET_FILE" | tr -d ' ')"
    echo ""
    echo "Matching Lines:               ${MATCHING}"
    echo "Source-Only Lines:            ${SOURCE_ONLY}"
    echo "Target-Only Lines:            ${TARGET_ONLY}"
    echo "Mismatched Lines:             ${MISMATCHED}"
    echo ""
    echo "============================================================================"
    echo "BREAKDOWN BY OBJECT TYPE"
    echo "============================================================================"
    echo ""
    printf "%-10s %-35s %10s %10s %10s\n" "Type" "Description" "SrcOnly" "TgtOnly" "Match"
    printf "%-10s %-35s %10s %10s %10s\n" "----------" "-----------------------------------" "-------" "-------" "------"
    for prefix in "${TYPE_PREFIXES[@]}"; do
        s=$(grep -c "^${prefix}|" "$SOURCE_ONLY_FILE" 2>/dev/null || true)
        t=$(grep -c "^${prefix}|" "$TARGET_ONLY_FILE" 2>/dev/null || true)
        m=$(grep -c "^${prefix}|" "$MATCHING_FILE" 2>/dev/null || true)
        total=$((s + t + m))
        if [ "$total" -gt 0 ]; then
            label=$(get_label "$prefix")
            printf "%-10s %-35s %10s %10s %10s\n" "$prefix" "$label" "$s" "$t" "$m"
        fi
    done
    echo ""
    echo "============================================================================"
    echo "DETAILED DIFFERENCES"
    echo "============================================================================"
    echo ""
    if [ "$MISMATCHED" -gt 0 ]; then
        echo "Differences - Objects/attributes only in SOURCE schema:"
        echo "--------------------------------------------------------"
        any_diff=false
        for prefix in "${TYPE_PREFIXES[@]}"; do
            count=$(grep -c "^${prefix}|" "$SOURCE_ONLY_FILE" 2>/dev/null || true)
            if [ "$count" -gt 0 ]; then
                any_diff=true
                label=$(get_label "$prefix")
                echo ""
                echo "[${prefix} - ${label}] (${count} line(s))"
                grep "^${prefix}|" "$SOURCE_ONLY_FILE" | head -50 | while IFS= read -r line; do
                    echo "  < $line"
                done
                if [ "$count" -gt 50 ]; then
                    echo "  ... and $((count - 50)) more line(s)"
                fi
            fi
        done
        if [ "$any_diff" = false ]; then
            echo "  (none)"
        fi
        echo ""
        echo "Differences - Objects/attributes only in TARGET schema:"
        echo "--------------------------------------------------------"
        any_diff=false
        for prefix in "${TYPE_PREFIXES[@]}"; do
            count=$(grep -c "^${prefix}|" "$TARGET_ONLY_FILE" 2>/dev/null || true)
            if [ "$count" -gt 0 ]; then
                any_diff=true
                label=$(get_label "$prefix")
                echo ""
                echo "[${prefix} - ${label}] (${count} line(s))"
                grep "^${prefix}|" "$TARGET_ONLY_FILE" | head -50 | while IFS= read -r line; do
                    echo "  > $line"
                done
                if [ "$count" -gt 50 ]; then
                    echo "  ... and $((count - 50)) more line(s)"
                fi
            fi
        done
        if [ "$any_diff" = false ]; then
            echo "  (none)"
        fi
    else
        echo "All schema objects match!"
    fi
    echo ""
    echo "============================================================================"
    echo "COMPILATION STATUS CHECK"
    echo "============================================================================"
    echo ""
    if [ "$SRC_ONLY_INV_COUNT" -gt 0 ] || [ "$TGT_ONLY_INV_COUNT" -gt 0 ] || [ "$BOTH_INV_COUNT" -gt 0 ]; then
        echo "Invalid (non-compiled) objects detected:"
        echo ""
        if [ "$SRC_ONLY_INV_COUNT" -gt 0 ]; then
            echo "WARNING: Objects invalid in SOURCE but valid in TARGET:"
            echo "  (source has compilation issues not present in target)"
            while IFS= read -r obj; do
                echo "  - $obj"
            done < "$SRC_ONLY_INVALID"
            echo ""
        fi
        if [ "$TGT_ONLY_INV_COUNT" -gt 0 ]; then
            echo "FAIL: Objects valid in SOURCE but invalid in TARGET:"
            echo "  (source compiles, target does not - regression detected!)"
            while IFS= read -r obj; do
                echo "  - $obj"
            done < "$TGT_ONLY_INVALID"
            echo ""
        fi
        if [ "$BOTH_INV_COUNT" -gt 0 ]; then
            echo "WARNING: Objects invalid in BOTH schemas:"
            echo "  (same issue exists in source and target)"
            while IFS= read -r obj; do
                echo "  - $obj"
            done < "$BOTH_INVALID"
            echo ""
        fi
    else
        echo "All compiled objects are in VALID status."
        echo ""
    fi
    echo "============================================================================"
    echo "OBJECT-LEVEL DIFFERENCE SUMMARY"
    echo "============================================================================"
    echo ""
    echo "Objects/attributes only in SOURCE schema:"
    report_list_source_objects() {
        local file="$1"
        local any=false
        for prefix in "${TYPE_PREFIXES[@]}"; do
            count=$(grep -c "^${prefix}|" "$file" 2>/dev/null || true)
            [ "$count" -eq 0 ] && continue
            any=true
            label=$(get_label "$prefix")
            echo "  ${label}:"
            if [ "$prefix" = "TAB_COL" ] || [ "$prefix" = "CONSTR" ]; then
                grep "^${prefix}|" "$file" | awk -F'|' '!seen[$3]++ {print "    - " $3}' | head -20
            elif [ "$prefix" = "SRC" ]; then
                grep "^${prefix}|" "$file" | awk -F'|' '!seen[$4]++ {print "    - " $4}' | head -20
            else
                grep "^${prefix}|" "$file" | awk -F'|' '!seen[$3]++ {print "    - " $3}' | head -20
            fi
        done
        if [ "$any" = false ]; then
            echo "  (none)"
        fi
    }
    report_list_source_objects "$SOURCE_ONLY_FILE"
    echo ""
    echo "Objects/attributes only in TARGET schema:"
    report_list_source_objects "$TARGET_ONLY_FILE"
    echo ""
    echo "============================================================================"
    echo "SUMMARY"
    echo "============================================================================"
    echo ""
    if [ "$OVERALL_FAIL" = false ]; then
        echo "RESULT: PASS - All schema objects match and are valid!"
        echo "Source and target schemas are structurally identical with no compilation issues."
    else
        echo "RESULT: FAIL - ${FAIL_REASON}"
        echo "  - Source-only fingerprint lines:  $SOURCE_ONLY"
        echo "  - Target-only fingerprint lines:  $TARGET_ONLY"
        echo "  - Matching fingerprint lines:     $MATCHING"
        if [ "$SRC_INV_COUNT" -gt 0 ] || [ "$TGT_INV_COUNT" -gt 0 ]; then
            echo "  - Source INVALID objects:         $SRC_INV_COUNT"
            echo "  - Target INVALID objects:         $TGT_INV_COUNT"
        fi
    fi
    echo "============================================================================"
} > "$REPORT_FILE"

echo ""
echo "Report saved to: $REPORT_FILE"
