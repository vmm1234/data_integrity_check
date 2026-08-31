#!/bin/bash
# ============================================================================
# Data Integrity Test Runner
# ============================================================================
# Reads test_config.csv (test case definitions), groups checks by test_id,
# runs each test via the appropriate check script, and saves logs + summary
# to the logs/ directory.
#
# Supports multiple checks per test_id via the check_order column.
# Rows sharing the same test_id are executed as sub-checks of one logical test.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config/test_config.csv"
LOG_DIR="${SCRIPT_DIR}/logs"
SUMMARY_FILE="${LOG_DIR}/summary.csv"
XML_FILE="${LOG_DIR}/test_results.xml"
STAGING_DIR="${LOG_DIR}/.staging"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

mkdir -p "$LOG_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

xml_escape() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

# ============================================================================
# parse_csv_line — Parse a CSV line with RFC 4180 double-quote support
# ============================================================================
# Handles:
#   - Unquoted fields:           a,b,c
#   - Quoted fields:             a,"b,c",d
#   - Doubled quotes in field:   a,"b""c",d  →  b"c
#
# Sets global array PARSED_FIELDS with the extracted field values.
# ============================================================================
parse_csv_line() {
    local line="$1"
    PARSED_FIELDS=()
    local field=""
    local in_quotes=false
    local i=0
    local len=${#line}

    while [ $i -lt $len ]; do
        local char="${line:$i:1}"

        if [ "$char" = '"' ]; then
            if [ "$in_quotes" = true ]; then
                # Doubled quote "" → literal quote
                if [ $((i + 1)) -lt $len ] && [ "${line:$((i + 1)):1}" = '"' ]; then
                    field="${field}\""
                    i=$((i + 2))
                else
                    in_quotes=false
                    i=$((i + 1))
                fi
            else
                in_quotes=true
                i=$((i + 1))
            fi
        elif [ "$char" = ',' ] && [ "$in_quotes" = false ]; then
            PARSED_FIELDS+=("$field")
            field=""
            i=$((i + 1))
        else
            field="${field}${char}"
            i=$((i + 1))
        fi
    done

    PARSED_FIELDS+=("$field")
}

# ============================================================================
# run_check — Execute a single check and set result/remark/source/target
# ============================================================================
# Arguments:
#   $1  test_id
#   $2  test_type (CSV|DB|XLS|SCRIPT)
#   $3  source_location
#   $4  source_name
#   $5  target_location
#   $6  target_name
#   $7  source_partition
#   $8  target_partition
#   $9  pre_test_script (used by SCRIPT type)
#   $10 check_order (for log file naming)
#
# Sets global variables: result, remark, source, target
# ============================================================================
run_check() {
    local _test_id="$1"
    local _test_type="$2"
    local _source_location="$3"
    local _source_name="$4"
    local _target_location="$5"
    local _target_name="$6"
    local _source_partition="$7"
    local _target_partition="$8"
    local _pre_test_script="$9"
    local _check_order="${10}"

    local _output=""
    local _ec=0
    local _log_suffix=""

    if [ -n "$_check_order" ]; then
        _log_suffix="_${_check_order}"
    fi

    case $_test_type in
        CSV)
            local _source_path="${_source_location}/${_source_name}"
            local _target_path="${_target_location}/${_target_name}"
            _output=$("${SCRIPT_DIR}/check_csv_integrity.sh" "$_source_path" "$_target_path" </dev/null 2>&1)
            _ec=$?
            echo "$_output"
            if [ $_ec -ne 0 ]; then
                result="FAIL"
                remark=$(echo "$_output" | grep -i "^ERROR" | head -1)
            elif echo "$_output" | grep -q "All data matches"; then
                result="PASS"
            else
                result="FAIL"
                remark=$(echo "$_output" | grep -o 'RESULT:[^,]*' | head -1)
            fi
            source="$_source_path"
            target="$_target_path"
            ;;
        DB)
            local _db_config="${SCRIPT_DIR}/config/db_config.conf"
            if [ ! -f "$_db_config" ]; then
                result="FAIL"
                remark="DB config not found: $_db_config"
                echo "ERROR: $remark"
            else
                _output=$("${SCRIPT_DIR}/check_data_integrity.sh" "$_db_config" "$_source_location" "$_source_name" "$_target_location" "$_target_name" "$_source_partition" "$_target_partition" </dev/null 2>&1)
                _ec=$?
                local _report_file="${SCRIPT_DIR}/data_integrity_report.txt"
                echo "$_output" > "$_report_file"
                if [ $_ec -ne 0 ]; then
                    result="FAIL"
                    remark=$(echo "$_output" | grep -i "^ERROR" | head -1)
                elif [ -f "$_report_file" ] && \
                     grep -qE 'Rows in Source Only:[[:space:]]*0' "$_report_file" && \
                     grep -qE 'Rows in Target Only:[[:space:]]*0' "$_report_file"; then
                    result="PASS"
                else
                    result="FAIL"
                    if [ -f "$_report_file" ]; then
                        remark=$(grep -E 'Rows in (Source|Target) Only:' "$_report_file" | tr '\n' '; ' | sed 's/; $//')
                    else
                        remark="Report file not found"
                    fi
                fi
            fi
            source="${_source_location}.${_source_name}"
            target="${_target_location}.${_target_name}"
            ;;
        XLS)
            local _source_path="${_source_location}/${_source_name}"
            local _target_path="${_target_location}/${_target_name}"
            _output=$(python3 "${SCRIPT_DIR}/check_excel_integrity.py" "$_source_path" "$_target_path" </dev/null 2>&1)
            _ec=$?
            echo "$_output"
            if [ $_ec -ne 0 ]; then
                result="FAIL"
                remark=$(echo "$_output" | grep -i "^ERROR" | head -1)
            elif echo "$_output" | grep -qE 'Mismatched Rows:[[:space:]]*0' && \
                 echo "$_output" | grep -qE 'Rows in Source[^:]*:[[:space:]]*0' && \
                 echo "$_output" | grep -qE 'Rows in Target[^:]*:[[:space:]]*0'; then
                result="PASS"
            else
                result="FAIL"
                remark=$(echo "$_output" | grep -E '(Mismatched|Rows in Source|Rows in Target)' | head -2 | tr '\n' '; ' | sed 's/; $//')
            fi
            source="$_source_path"
            target="$_target_path"
            ;;
        SCRIPT)
            if [ -z "$_pre_test_script" ]; then
                result="FAIL"
                remark="No script specified in pre_test_script column"
                echo "ERROR: SCRIPT test type requires pre_test_script column to be set"
            else
                local _script_log="${LOG_DIR}/${_test_id}_script${_log_suffix}.log"
                echo "[Script] $_pre_test_script"
                eval "$_pre_test_script" > "$_script_log" 2>&1
                _ec=$?
                if [ $_ec -ne 0 ]; then
                    result="FAIL"
                    remark="Script failed (exit $_ec): $(grep -iE '(error|failed|exception)' "$_script_log" | head -1)"
                    echo "[Script] FAIL — exit code $_ec — see log: $_script_log"
                else
                    result="PASS"
                    echo "[Script] PASS — log: $_script_log"
                fi
            fi
            source="${_source_location}/${_source_name}"
            target="${_target_location}/${_target_name}"
            ;;
        *)
            result="FAIL"
            remark="Unknown test type: $_test_type"
            echo "ERROR: Unknown test type: $_test_type"
            source="${_source_location}/${_source_name}"
            target="${_target_location}/${_target_name}"
            ;;
    esac

    local _output_file="${LOG_DIR}/${_test_id}_${_test_type}${_log_suffix}.log"
    if [ "$_test_type" = "SCRIPT" ]; then
        local _script_log="${LOG_DIR}/${_test_id}_script${_log_suffix}.log"
        cp "$_script_log" "$_output_file" 2>/dev/null || true
    else
        echo "$_output" > "$_output_file"
    fi
    if [ "$_test_type" = "DB" ] && [ -f "${SCRIPT_DIR}/data_integrity_report.txt" ]; then
        cp "${SCRIPT_DIR}/data_integrity_report.txt" "${LOG_DIR}/${_test_id}_${_test_type}${_log_suffix}_report.txt"
    fi
}

# ============================================================================
# PASS 1: Read config and group rows by test_id
# ============================================================================
declare -a TEST_IDS_ORDER=()
UNIQUE_IDS=""

while IFS= read -r _csv_line; do
    [ -z "$_csv_line" ] && continue

    parse_csv_line "$_csv_line"
    test_id="${PARSED_FIELDS[0]}"
    test_key="${PARSED_FIELDS[1]}"
    blocked_case_flag="${PARSED_FIELDS[2]}"
    pre_test_script="${PARSED_FIELDS[3]}"
    check_order="${PARSED_FIELDS[4]}"
    test_type="${PARSED_FIELDS[5]}"
    source_location="${PARSED_FIELDS[6]}"
    source_name="${PARSED_FIELDS[7]}"
    target_location="${PARSED_FIELDS[8]}"
    target_name="${PARSED_FIELDS[9]}"
    source_partition="${PARSED_FIELDS[10]}"
    target_partition="${PARSED_FIELDS[11]}"
    requirement="${PARSED_FIELDS[12]}"
    expected_result="${PARSED_FIELDS[13]}"

    [ -z "$test_id" ] && continue

    # Track unique test_ids in order of first appearance (bash 3.2 compatible)
    if ! echo "$UNIQUE_IDS" | grep -qw "$test_id"; then
        UNIQUE_IDS="${UNIQUE_IDS} ${test_id}"
        TEST_IDS_ORDER+=("$test_id")
    fi

    # Write row to staging file (0x1F-delimited) for this test_id
    printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
        "$check_order" "$test_type" "$source_location" "$source_name" \
        "$target_location" "$target_name" "$source_partition" "$target_partition" \
        "$pre_test_script" "$test_key" "$blocked_case_flag" "$requirement" \
        "$expected_result" >> "${STAGING_DIR}/${test_id}"
done < <(tail -n +2 "$CONFIG_FILE")

# ============================================================================
# PASS 2: Execute each test_id group
# ============================================================================
total=0
passed=0
failed=0
xml_content=""
total_elapsed=0

echo '"test_id","test_type","source","target","result","test_complete_time","remark","blocked_case_flag","check_order"' > "$SUMMARY_FILE"

for test_id in "${TEST_IDS_ORDER[@]}"; do
    staging_file="${STAGING_DIR}/${test_id}"

    # Read all rows for this test_id, extract shared metadata from first row
    first_row=true
    first_type=""
    test_key=""
    blocked_case_flag=""
    pre_test_script=""
    requirement=""
    expected_result=""
    has_check_order=false
    group_type_list=""
    group_source_list=""
    group_target_list=""
    group_result="PASS"
    group_remarks=""
    group_failed_count=0
    group_check_count=0
    group_start_time=$(date +%s)

    while IFS=$'\x1f' read -r check_order stype sloc sname tloc tname spart tpart pscript tkey bflag req eresult; do
        # Shared metadata from first row
        if [ "$first_row" = true ]; then
            first_type="$stype"
            test_key="$tkey"
            blocked_case_flag="$bflag"
            pre_test_script="$pscript"
            requirement="$req"
            expected_result="$eresult"
            first_row=false
        fi

        # Track whether any row has a check_order
        [ -n "$check_order" ] && has_check_order=true

    done < "$staging_file"

    # ── BLOCKED ──────────────────────────────────────────────────────
    if [ "$blocked_case_flag" = "Y" ]; then
        echo ""
        echo "========================================================================"
        echo "BLOCKED: $test_id — blocked_case_flag=Y, skipping"
        echo "------------------------------------------------------------------------"
        # Collect types for summary
        blocked_types=$(awk -F'\x1f' '{printf "%s%s", (NR>1?",":""), $2}' "$staging_file")
        echo "\"$test_id\",\"$blocked_types\",\"\",\"\",\"\",\"BLOCKED\",\"$(date '+%Y-%m-%d %H:%M:%S')\",\"blocked_case_flag=Y\"," >> "$SUMMARY_FILE"
        echo "------------------------------------------------------------------------"
        echo "Result: BLOCKED"
        echo ""
        continue
    fi

    # ── RUN GROUP ────────────────────────────────────────────────────
    total=$((total + 1))
    echo ""
    echo "========================================================================"
    if [ "$has_check_order" = true ]; then
        echo "Running: $test_id (multi-check group)"
    else
        echo "Running: $test_id (standalone)"
    fi
    echo "------------------------------------------------------------------------"

    # Pre-test script (once per group)
    pre_test_ec=0
    pre_test_log="${LOG_DIR}/${test_id}_pre_test.log"
    if [ -n "$pre_test_script" ] && [ "$first_type" != "SCRIPT" ]; then
        echo "[Pre-test] $pre_test_script"
        eval "$pre_test_script" > "$pre_test_log" 2>&1
        pre_test_ec=$?
        if [ $pre_test_ec -ne 0 ]; then
            echo "[Pre-test] FAIL — see log: $pre_test_log"
            group_result="FAIL"
            group_remarks="Pre-test failed: $(grep -iE '(error|failed|exception)' "$pre_test_log" | head -1)"
        else
            echo "[Pre-test] PASS — log: $pre_test_log"
        fi
    fi

    # Sort staging rows by check_order (empty orders sort last)
    sorted_rows=$(sort -t$'\x1f' -k1,1n -s "$staging_file" 2>/dev/null || sort -t$'\x1f' -k1,1 "$staging_file")

    # Execute each sub-check
    while IFS=$'\x1f' read -r check_order stype sloc sname tloc tname spart tpart pscript tkey bflag req eresult; do
        group_check_count=$((group_check_count + 1))

        echo ""
        echo "--- Sub-check #${group_check_count}: ${stype} (order: ${check_order:-standalone}) ---"

        result=""
        remark=""
        source=""
        target=""

        if [ "$pre_test_ec" -ne 0 ]; then
            result="FAIL"
            remark="Skipped: pre-test script failed"
        else
            run_check "$test_id" "$stype" "$sloc" "$sname" "$tloc" "$tname" "$spart" "$tpart" "$pscript" "$check_order"
        fi

        # Negative case inversion
        if [ "$expected_result" = "FAIL" ] && [ -n "$result" ]; then
            if [ "$result" = "PASS" ]; then
                result="FAIL"
                remark="Negative case: expected differences but data matched"
            elif [ "$result" = "FAIL" ]; then
                result="PASS"
                remark="Negative case: differences correctly detected"
            fi
        fi

        # Fallback remark
        if [ -z "$remark" ] && [ "$result" = "FAIL" ]; then
            remark="Check failed (see log for details)"
        fi
        # Strip ANSI escape codes
        remark=$(echo "$remark" | sed 's/\x1b\[[0-9;]*m//g')
        # Sanitize for CSV
        remark="${remark//,/;}"

        # Aggregate into group
        if [ -n "$group_type_list" ]; then
            group_type_list="${group_type_list},${stype}"
        else
            group_type_list="$stype"
        fi

        if [ -n "$group_source_list" ]; then
            group_source_list="${group_source_list};${source}"
        else
            group_source_list="$source"
        fi

        if [ -n "$group_target_list" ]; then
            group_target_list="${group_target_list};${target}"
        else
            group_target_list="$target"
        fi

        if [ "$result" = "FAIL" ]; then
            group_result="FAIL"
            group_failed_count=$((group_failed_count + 1))
            if [ -n "$group_remarks" ]; then
                group_remarks="${group_remarks}; ${stype}: ${remark}"
            else
                group_remarks="${stype}: ${remark}"
            fi
        fi

        echo "Result: $result"
        if [ -n "$remark" ]; then
            echo "Remark: $remark"
        fi

    done <<< "$sorted_rows"

    group_end_time=$(date +%s)
    group_duration=$((group_end_time - group_start_time))
    total_elapsed=$((total_elapsed + group_duration))

    # ── AGGREGATE RESULT ─────────────────────────────────────────────
    test_complete_time=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$group_result" = "PASS" ]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
    fig

    echo "------------------------------------------------------------------------"
    echo "Overall: $group_result ($group_check_count sub-checks, $group_failed_count failed)"
    echo "Time:    $test_complete_time"
    if [ -n "$group_remarks" ]; then
        echo "Remark:  $group_remarks"
    fi

    # Summary CSV row
    group_remarks_csv="${group_remarks//,/;}"
    echo "\"$test_id\",\"$group_type_list\",\"$group_source_list\",\"$group_target_list\",\"$group_result\",\"$test_complete_time\",\"$group_remarks_csv\",\"$blocked_case_flag\"," >> "$SUMMARY_FILE"

    # ── XML TESTCASE ─────────────────────────────────────────────────
    esc_test_id=$(xml_escape "$test_id")
    esc_classname=$(xml_escape "$group_type_list")
    esc_remark=$(xml_escape "$group_remarks")
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

    xml_time=$(awk "BEGIN { printf \"%.3f\", $group_duration }")

    xml_failure=""
    if [ "$group_result" = "FAIL" ]; then
        xml_failure="            <failure message=\"${esc_remark}\" type=\"FAIL\"/>
"
    fi

    xml_content="${xml_content}        <testcase name=\"${esc_test_id}\" classname=\"${esc_classname}\" time=\"${xml_time}\">
${xml_props}${xml_failure}        </testcase>
"
done

# ============================================================================
# CLEANUP
# ============================================================================
rm -rf "$STAGING_DIR"

# ============================================================================
# FINAL OUTPUT
# ============================================================================
echo ""
echo "========================================================================"
echo "RUN COMPLETE"
echo "========================================================================"
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

# Write Xray extended JUnit XML report
total_time=$(awk "BEGIN { printf \"%.3f\", $total_elapsed }")
cat > "$XML_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
    <testsuite name="Data Integrity Check" tests="$total" failures="$failed" errors="0" time="$total_time">
${xml_content}    </testsuite>
</testsuites>
EOF

echo "Results summary: $SUMMARY_FILE"
echo "  Summary:  $(wc -l < "$SUMMARY_FILE") entries (incl. header)"
echo "  XML:      $XML_FILE"
echo "  Logs:     $LOG_DIR/<test_id>_<type>.log"
