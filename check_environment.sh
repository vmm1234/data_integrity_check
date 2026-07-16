#!/bin/bash
# ============================================================================
# check_environment.sh — Environment Validation Script
# ============================================================================
# Reads env_test_cases.csv, runs file presence, permission, and command
# checks, and produces both a human-readable report (stdout) and a
# JUnit/Xray XML report (--output).
#
# USAGE:
#   ./check_environment.sh [--output report.xml]
#
# CSV columns:
#   test_id,test_key,check_type,target,expected,requirement
#
# check_type values:
#   exists       — target path must exist
#   not_exists   — target path must NOT exist
#   perm         — target file must have expected octal permission (e.g. 755)
#   cmd          — run 'expected' as a command, must exit 0
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/env_test_cases.csv"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

OUTPUT_FILE=""

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            shift
            OUTPUT_FILE="$1"
            ;;
        --help|-h)
            echo "Usage: $0 [--output report.xml]"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: $0 [--output report.xml]"
            exit 1
            ;;
    esac
    shift
done

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

xml_escape() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

TOTAL=0
PASSED=0
FAILED=0
TOTAL_ELAPSED=0
XML_CONTENT=""
HUMAN_LINES=""

echo ""
echo "============================================================================"
echo "ENVIRONMENT CHECK"
echo "============================================================================"
echo "Config: $CONFIG_FILE"
echo "Report Generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================================"
echo ""

# Read CSV line by line (skip header)
{
    read
    while IFS=',' read -r test_id test_key check_type target expected requirement; do

        # Trim whitespace from each field
        test_id=$(echo "$test_id" | xargs)
        check_type=$(echo "$check_type" | xargs)
        target=$(echo "$target" | xargs)
        expected=$(echo "$expected" | xargs)

        TOTAL=$((TOTAL + 1))
        result="PASS"
        remark=""

        start_time=$(date +%s%N 2>/dev/null || echo 0)

        case "$check_type" in
            exists)
                if [ -e "$target" ]; then
                    result="PASS"
                    remark="Path exists"
                else
                    result="FAIL"
                    remark="Path not found: $target"
                fi
                ;;
            not_exists)
                if [ ! -e "$target" ]; then
                    result="PASS"
                    remark="Path does not exist (expected)"
                else
                    result="FAIL"
                    remark="Path exists but should not: $target"
                fi
                ;;
            perm)
                if [ ! -e "$target" ]; then
                    result="FAIL"
                    remark="Path not found: $target"
                else
                    actual_perm=$(stat -f "%A" "$target" 2>/dev/null || echo "")
                    if [ "$actual_perm" = "$expected" ]; then
                        result="PASS"
                        remark="Permission is $expected"
                    else
                        result="FAIL"
                        remark="Expected permission $expected, got $actual_perm"
                    fi
                fi
                ;;
            cmd)
                cmd_output=$(eval "$expected" 2>&1)
                cmd_ec=$?
                if [ $cmd_ec -eq 0 ]; then
                    result="PASS"
                    remark="Command exited with code 0"
                else
                    result="FAIL"
                    remark="Command exited with code $cmd_ec: $expected"
                fi
                ;;
            *)
                result="FAIL"
                remark="Unknown check_type: $check_type"
                ;;
        esac

        end_time=$(date +%s%N 2>/dev/null || echo 0)
        if [[ "$start_time" =~ ^[0-9]+$ ]] && [[ "$end_time" =~ ^[0-9]+$ ]]; then
            duration_ns=$((end_time - start_time))
            duration=$(awk "BEGIN { printf \"%.3f\", $duration_ns / 1000000000 }")
        else
            duration="0.001"
        fi
        TOTAL_ELAPSED=$(awk "BEGIN { printf \"%.3f\", $TOTAL_ELAPSED + $duration }")

        # Color-coded label
        check_label=$(echo "$check_type" | tr '[:lower:]' '[:upper:]')
        if [ "$result" = "PASS" ]; then
            status_display="${GREEN}PASS${NC}"
        else
            status_display="${RED}FAIL${NC}"
        fi

        HUMAN_LINES="${HUMAN_LINES}  [${check_label}]  ${test_id}  ${target}  ${status_display}"
        if [ "$result" = "FAIL" ] && [ -n "$remark" ]; then
            HUMAN_LINES="${HUMAN_LINES}  (${remark})"
        fi
        HUMAN_LINES="${HUMAN_LINES}"$'\n'

        # Build XML testcase element (Xray extended JUnit format)
        esc_test_id=$(xml_escape "$test_id")
        esc_check_type=$(xml_escape "$check_type")
        esc_remark=$(xml_escape "$remark")
        esc_test_key=$(xml_escape "$test_key")
        esc_requirement=$(xml_escape "$requirement")

        xml_props=""
        if [ -n "$test_key" ] || [ -n "$requirement" ]; then
            xml_props="            <properties>
"
            if [ -n "$test_key" ]; then
                xml_props="${xml_props}                <property name=\"test_key\" value=\"${esc_test_key}\"/>
"
            fi
            if [ -n "$requirement" ]; then
                if echo "$esc_requirement" | grep -q ","; then
                    xml_props="${xml_props}                <property name=\"requirements\" value=\"${esc_requirement}\"/>
"
                else
                    xml_props="${xml_props}                <property name=\"requirement\" value=\"${esc_requirement}\"/>
"
                fi
            fi
            xml_props="${xml_props}            </properties>
"
        fi

        xml_failure=""
        if [ "$result" = "FAIL" ]; then
            xml_failure="            <failure message=\"${esc_remark}\" type=\"FAIL\"/>
"
        fi

        XML_CONTENT="${XML_CONTENT}        <testcase name=\"${esc_test_id}\" classname=\"${esc_check_type}\" time=\"${duration}\">
${xml_props}${xml_failure}        </testcase>
"

        if [ "$result" = "PASS" ]; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
        fi

    done
} < "$CONFIG_FILE"

# Print human-readable report
echo -n "$HUMAN_LINES"
echo ""
echo "============================================================================"
echo "SUMMARY"
echo "============================================================================"
echo "Total: $TOTAL | Passed: $PASSED | Failed: $FAILED"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}RESULT: PASS - All environment checks passed${NC}"
    echo ""
else
    echo -e "${RED}RESULT: FAIL - $FAILED check(s) failed${NC}"
    echo ""
fi
echo "============================================================================"

# Write JUnit Xray XML report
if [ -n "$OUTPUT_FILE" ]; then
    total_time=$(awk "BEGIN { printf \"%.3f\", $TOTAL_ELAPSED }")
    cat > "$OUTPUT_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
    <testsuite name="Environment Check" tests="$TOTAL" failures="$FAILED" errors="0" time="$total_time">
${XML_CONTENT}    </testsuite>
</testsuites>
EOF
    echo "XML report saved to: $OUTPUT_FILE"
fi

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
