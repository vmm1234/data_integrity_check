# Data Integrity Check Tools

Scripts for checking data integrity between different data sources.

## Overview

| Script | Data Source | Comparison Strategy |
|--------|-------------|---------------------|
| `check_data_integrity.sql` | Oracle Database Tables | MINUS/INTERSECT (set-based) |
| `check_csv_integrity.sh` | CSV Files | Sorted diff |
| `check_excel_integrity.py` | Excel Files (XLS/XLSX) | Position-based |
| `check_schema_integrity.sh` | Oracle Schema Objects | Fingerprint diff (`comm`) |
| `check_environment.sh` | File System / Commands | Existence, permission, command execution |

## Quick Start

```bash
# 1. Oracle Database Data (requires sqlcl)
./check_data_integrity.sh SOURCE_SCHEMA SOURCE_TABLE TARGET_SCHEMA TARGET_TABLE

# 2. CSV Files
./check_csv_integrity.sh test_csv/source.csv test_csv/target.csv

# 3. Excel Files (requires pandas, openpyxl)
python3 check_excel_integrity.py test_excel/source.xlsx test_excel/target.xlsx --verbose

# 4. Oracle Schema Objects (requires sqlcl/sqlplus)
./check_schema_integrity.sh config/db_config.conf HR_PROD HR_STAGING

# 5. Environment Check (file presence, permissions, commands)
./check_environment.sh --output logs/env_report.xml
```

## Virtual Environment Setup (Offline)

The `wheel/` folder contains pre-downloaded `.whl` files for Excel dependencies.
Use them to create an isolated Python environment without internet access.

### Create & Activate

```bash
# Create virtual environment
python3 -m venv venv

# Activate it
source venv/bin/activate        # macOS / Linux
# .\venv\Scripts\activate       # Windows

# Upgrade pip inside the venv
python3 -m pip install --upgrade pip

# Install from local wheel files (offline)
python3 -m pip install --no-index --find-links wheel/ -r requirements.txt
```

### Verify

```bash
python3 check_excel_integrity.py test_excel/source.xlsx test_excel/target.xlsx --verbose
```

### Wheel Contents (`wheel/`)

| Package | Required By |
|---------|-------------|
| `pandas` | DataFrame comparison engine |
| `openpyxl` | XLSX file reader |
| `numpy` | pandas dependency |
| `python-dateutil` | pandas dependency |
| `pytz` | pandas dependency |
| `six` | python-dateutil dependency |
| `tzdata` | pandas IANA timezone data |
| `et-xmlfile` | openpyxl dependency |

> **Note:** The `numpy` and `pandas` wheels in `wheel/` are built for **macOS ARM64 (Python 3.9)**.  
> On a different OS/arch/Python version, re-download with:
> ```bash
> python3 -m pip download -d wheel/ -r requirements.txt
> ```

---

## 1. Oracle Database: `check_data_integrity.sql`

Compares data between two Oracle database tables. Automatically discovers columns from table metadata. Uses `MINUS`/`INTERSECT` for efficient set-based comparison without false cascading mismatches.

### Prerequisites

- Oracle Database access
- [SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) installed
- Read permissions on source and target tables

### Setup

Edit `config/db_config.conf` with connection details for both source and target databases:

```bash
SOURCE_DB_USER="source_user"
SOURCE_DB_PASSWORD="source_password"
SOURCE_DB_HOST="db1.example.com"
SOURCE_DB_PORT="1521"
SOURCE_DB_SERVICE="xe"

TARGET_DB_USER="target_user"
TARGET_DB_PASSWORD="target_password"
TARGET_DB_HOST="db2.example.com"
TARGET_DB_PORT="1521"
TARGET_DB_SERVICE="xe"
```

### Usage

```bash
# Using wrapper script (recommended)
chmod +x check_data_integrity.sh
./check_data_integrity.sh config/db_config.conf TEST USERS TEST USERS2

# Using sqlcl directly
sqlcl user/pass@db @check_data_integrity.sql SOURCE_SCHEMA SOURCE_TABLE TARGET_SCHEMA TARGET_TABLE
```

### Output

Report saved to `logs/data_integrity_report.txt` with:
- Row count summary
- Matching, source-only, and target-only row counts
- Detailed mismatch report (via MINUS comparison)

---

## 2. CSV Files: `check_csv_integrity.sh`

Compares data between two CSV files. Automatically discovers columns from the header row. Uses sorted diff to avoid position-based cascading mismatches.

### Prerequisites

- Bash shell (Linux, macOS, or WSL on Windows)
- Standard Unix tools: `awk`, `sort`, `comm`, `head`, `tail`

### Usage

```bash
chmod +x check_csv_integrity.sh

# Compare sample files
./check_csv_integrity.sh test_csv/source.csv test_csv/target.csv

# Compare your files
./check_csv_integrity.sh /path/to/source.csv /path/to/target.csv

# Verify identical files produce no mismatches
./check_csv_integrity.sh test_csv/source.csv test_csv/source.csv
```

### Test Data

The `test_csv/` folder contains sample files with:
- **source.csv** (20 rows): Complete dataset
- **target.csv** (20 rows): Row 5 email changed, row 12 deleted, row 21 added

### Output

Color-coded report with:
- File information and column names
- Row count summary
- Matching, source-only, and target-only row counts
- Column-by-column mismatch details
- Final summary (green = match, red = mismatches)

---

## 3. Excel Files: `check_excel_integrity.py`

Compares data between two Excel files (XLS/XLSX). Automatically discovers sheets and columns. Performs position-based row-by-row and cell-by-cell comparison.

### Prerequisites

- Python 3.6+
- Required packages: `pandas`, `openpyxl`

### Installation

```bash
pip3 install pandas openpyxl
```

### Usage

```bash
# Compare sample files
python3 check_excel_integrity.py test_excel/source.xlsx test_excel/target.xlsx --verbose

# Compare specific sheet
python3 check_excel_integrity.py source.xlsx target.xlsx --sheet Sheet1

# Generate HTML report
python3 check_excel_integrity.py source.xlsx target.xlsx --output report.html
```

### Test Data

The `test_excel/` folder contains sample files with:
- **source.xlsx** (20 rows): Complete employee data (id, name, email, department, salary)
- **target.xlsx** (20 rows): Row 5 email changed, row 7 salary changed, row 12 deleted, row 21 added

### Output

Report with:
- File information and sheet names
- Row count summary
- Matching, source-only, target-only, and mismatched row counts
- Detailed cell-level mismatch report (with `--verbose`)
- Column-by-column mismatch summary
- Optional HTML report (with `--output`)

---

---

## 4. Oracle Schema Objects: `check_schema_integrity.sh`

Compares object definitions between two Oracle schemas on **different databases**. Exports metadata from each schema's data dictionary, generates canonical "fingerprints" per object, and uses sorted `comm`-based diff to detect structural differences.

### Object Types Compared

| Object Type | What's Checked | Dictionary View |
|-------------|----------------|-----------------|
| **TABLE** | Columns (name, type, length, precision, scale, nullable, default) | `ALL_TAB_COLUMNS` |
| **TABLE** | Constraints (PK, FK, UNIQUE, CHECK — columns, referenced table, search condition) | `ALL_CONSTRAINTS`, `ALL_CONS_COLUMNS` |
| **VIEW** | View name | `ALL_VIEWS` |
| **PROCEDURE / FUNCTION / PACKAGE / TYPE** | Full source code, line by line | `ALL_SOURCE` |
| **TRIGGER** | Trigger name, table, type, event, status | `ALL_TRIGGERS` |
| **SEQUENCE** | Min, max, increment, cache, cycle, order | `ALL_SEQUENCES` |
| **INDEX** | Uniqueness, type, visibility, columns | `ALL_INDEXES`, `ALL_IND_COLUMNS` |
| **SYNONYM** | Target owner, table name, db_link | `ALL_SYNONYMS` |
| **MATERIALIZED VIEW** | Materialized view name | `ALL_MVIEWS` |
| **DIRECTORY** | Directory name and OS path | `DBA_DIRECTORIES` |
| **GRANTS** | Object privileges, role grants, system privileges granted to schema | `DBA_TAB_PRIVS`, `DBA_ROLE_PRIVS`, `DBA_SYS_PRIVS` |
| **PARAMETER** | Database instance parameter names and values | `V$PARAMETER` |
| **All Compiled Objects** | Compilation status (VALID / INVALID) | `ALL_OBJECTS` |

### Prerequisites

- Oracle Database access on both source and target
- [SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) or SQL\*Plus installed
- Read permissions on data dictionary views (`ALL_*` views)
- DBA privilege on both databases (required for `DBA_DIRECTORIES`, `DBA_TAB_PRIVS`, `DBA_ROLE_PRIVS`, `DBA_SYS_PRIVS`)
- SELECT privilege on `V$PARAMETER`

### Setup

Edit `config/db_config.conf` with connection details for both databases:

```bash
SOURCE_DB_USER="source_user"
SOURCE_DB_PASSWORD="source_password"
SOURCE_DB_HOST="db1.example.com"
SOURCE_DB_PORT="1521"
SOURCE_DB_SERVICE="xe"

TARGET_DB_USER="target_user"
TARGET_DB_PASSWORD="target_password"
TARGET_DB_HOST="db2.example.com"
TARGET_DB_PORT="1521"
TARGET_DB_SERVICE="xe"
```

### Usage

```bash
chmod +x check_schema_integrity.sh

# Compare all objects between two schemas
./check_schema_integrity.sh config/db_config.conf HR_PROD HR_STAGING
```

### How It Works

1. `export_schema_objects.sql` connects to each database and queries the data dictionary for all object types
2. Each object detail (column, constraint, source line, etc.) is written as a pipe-delimited "fingerprint" line
3. INVALID-status code objects are automatically separated from the main comparison and compared independently by object name and type
4. The shell wrapper sorts all fingerprints from each schema, then uses `comm` to find matching, source-only, and target-only lines
5. A color-coded report is printed with summary counts, breakdown by object type, detailed grouped diff, and compilation status

### Output

Color-coded report with:
- Connection info for both databases
- Fingerprint line summary (matching, source-only, target-only)
- Breakdown by object type
- Detailed diff grouped by type (up to 50 lines per type, `>` and `<` markers)
- **Compilation status check** — detects INVALID objects in each schema:
  - WARNING: objects invalid in source but valid in target
  - FAIL: objects valid in source but invalid in target (regression)
  - WARNING: objects invalid in both schemas
- Object-level summary listing affected objects
- Final PASS/FAIL verdict
- Report saved to `logs/data_integrity_report.txt`

---

## 5. Environment Check: `check_environment.sh`

Validates the runtime environment by checking file/folder presence, file permissions, and command executability. Reads test cases from `config/env_test_cases.csv` and produces both a color-coded human report (stdout) and a JUnit/Xray XML report (`--output`).

### Test Case CSV (`config/env_test_cases.csv`)

| Column | Description |
|--------|-------------|
| `test_id` | Unique test case ID |
| `test_key` | Xray issue key (optional) |
| `check_type` | `exists`, `not_exists`, `perm`, or `cmd` |
| `target` | File/directory path, or command name |
| `expected` | For `perm`: expected octal permission (e.g. `755`). For `cmd`: full command to run (e.g. `sqlplus -V`). Blank for `exists`/`not_exists`. |
| `requirement` | Xray requirement key (optional) |

### Check Types

| Type | What It Does |
|------|-------------|
| `exists` | Passes if `target` path exists |
| `not_exists` | Passes if `target` path does **not** exist |
| `perm` | Passes if `target` file's octal permission matches `expected` |
| `cmd` | Runs `expected` as a command, passes if exit code = 0 |

### Prerequisites

- Bash shell (Linux, macOS, or WSL)
- Standard Unix tools: `stat`, `sed`

### Usage

```bash
# Run all checks, print report to stdout
./check_environment.sh

# Run all checks and save JUnit XML report
./check_environment.sh --output logs/env_report.xml
```

### Output

Color-coded console report with per-check PASS/FAIL status and a summary. When `--output` is specified, a JUnit/Xray XML file is written:

```xml
<testcase name="ENV001" classname="exists" time="0.002">
</testcase>
<testcase name="ENV005" classname="perm" time="0.003">
    <failure message="Expected permission 644, got 600" type="FAIL"/>
</testcase>
```

Exit code 0 if all checks pass, non-zero if any fail.

### Test Data

`config/env_test_cases.csv` includes sample checks:
- File presence: `run_check_integrity.sh` and `logs/` should exist
- File absence: `temp/` should not exist
- Permissions: `run_check_integrity.sh` should be `755`, `config/test_config.csv` should be `644`
- Commands: `python3 --version` should succeed, `sqlplus -V` will fail if not installed

---

## 6. Test Runner: `run_check_integrity.sh`

Automates execution of data integrity and validation test cases. Reads `config/test_config.csv`, dispatches each test to the appropriate check script, and aggregates results into a JUnit/Xray XML report.

### Test Case CSV (`config/test_config.csv`)

| Column | Description |
|--------|-------------|
| `test_id` | Test case ID. Rows with the same `test_id` are grouped as one logical test when `check_order` is set. |
| `test_key` | Xray issue key (optional, mapped to XML `<property name="test_key">`) |
| `blocked_case_flag` | `Y` to skip this test case (omitted from execution and XML) |
| `pre_test_script` | Command or script path to run **before** executing the test case (shared across all sub-checks in a group) |
| `check_order` | Integer controlling execution order within a group. Empty = standalone test. Rows sharing a `test_id` with non-empty `check_order` values run as sub-checks of one logical test. |
| `test_type` | `CSV`, `DB`, `XLS`, or `SCRIPT` (see below) |
| `source_location` / `source_name` | Source file or table path |
| `target_location` / `target_name` | Target file or table path |
| `source_partition` | Source partition (DB type only) |
| `target_partition` | Target partition (DB type only) |
| `requirement` | Xray requirement key (optional, mapped to XML `<property name="requirement">`) |
| `expected_result` | `PASS` or empty = normal case (data should match). `FAIL` = negative case (data should differ; result is inverted) |

### Features

**Blocked Cases** — Set `blocked_case_flag=Y` to skip a test. The test is logged as `BLOCKED` in the summary CSV and omitted entirely from the XML report.

**Pre-test Scripts** — Specify a script/command in `pre_test_script` to run before the main check. If it exits non-zero, the test is marked `FAIL`. All stdout/stderr output is captured to `logs/<test_id>_pre_test.log`; only a summary line is printed to the console. Useful for data setup, file staging, or preconditions.

Example — TC005 in `config/test_config.csv` uses `./test_scripts/test1.sh` as a pre-test script that:
1. Copies `test_input/test01.csv` to the project root as `source.csv`
2. Runs `test_scripts/test_script2.sh` to generate `target.csv`
3. Verifies both files exist before the CSV comparison runs

**SCRIPT Test Type** — A standalone test type that runs a script **without** any data comparison. The script path is taken from the `pre_test_script` column. Result is determined by exit code only: exit 0 = PASS, non-zero = FAIL. Full output is saved to `logs/<test_id>_script.log`. Useful for setup steps, smoke tests, or custom validations that don't compare source/target data.

**Multi-Check Test Cases** — Run multiple integrity checks under a single `test_id`. Set the `check_order` column (1-based integer) on each row sharing the same `test_id`. The runner groups them, runs the pre-test script once, then executes each sub-check in `check_order` sequence. All sub-checks run even if earlier ones fail. The overall result is PASS only if **all** sub-checks pass; failed remarks are semicolon-joined with type prefix (e.g. `CSV: 2 source-only rows; DB: Rows in Source Only: 3`). One XML testcase and one summary CSV row are emitted per `test_id`.

Example — A grouped test that validates the same data via CSV and DB:

```csv
TC001,,,,1,CSV,test_csv,source.csv,test_csv,target.csv,,,,
TC001,,,,2,DB,TEST,USERS,TEST,USERS2,,,CALC-123,
```

**Negative Cases** — Set `expected_result=FAIL` to indicate a test where data should differ. The result is inverted: if the check detects differences, the test reports PASS; if data matches unexpectedly, the test reports FAIL. Useful for verifying the tool catches known issues.

**Xray Integration** — `test_key` and `requirement` columns map to Xray XML properties. For multi-check groups, `classname` contains the comma-separated list of types:

```xml
<testcase name="TC001" classname="CSV,DB" time="1.234">
    <properties>
        <property name="test_key" value="PROJ-123"/>
        <property name="requirement" value="CALC-123"/>
    </properties>
</testcase>
```

### Usage

```bash
# Run all test cases defined in config/test_config.csv
./run_check_integrity.sh
```

Results are written to:
- `logs/summary.csv` — per-test summary (one row per `test_id`)
- `logs/test_results.xml` — Xray JUnit XML report
- `logs/<test_id>_<type>.log` — full output per test (standalone)
- `logs/<test_id>_<type>_<order>.log` — full output per sub-check (multi-check groups)
- `logs/<test_id>_pre_test.log` — pre-test script output (when `pre_test_script` is set)
- `logs/<test_id>_script.log` — SCRIPT test type output (standalone)
- `logs/<test_id>_script_<order>.log` — SCRIPT test type output (multi-check groups)

---

## Comparison Table

| Feature | SQL Data | CSV | Excel | Schema | Environment |
|---------|----------|-----|-------|--------|-------------|
| Column Discovery | Automatic | Automatic | Automatic | Automatic | N/A |
| Row Matching | Set-based (MINUS) | Sorted diff | Position-based | Fingerprint diff (`comm`) | Existence / Permission / Command |
| Cascading False Mismatches | No | No | Yes (when rows added/deleted) | No | No |
| Multi-sheet / Multi-object Support | N/A | N/A | Yes | Yes (13 object types + compilation check) | Yes (batch from CSV) |
| Color Output | No | Yes | No (HTML optional) | Yes | Yes |
| Cross-Database | Yes (via CSV export) | N/A | N/A | Yes (native) | N/A |

---

## Project Structure

```
data_integrity_check/
├── README.md                       # This file
├── requirements.txt                # Python dependencies
├── run_check_integrity.sh          # Test runner (reads config/test_config.csv)
├── check_environment.sh            # Environment validation script
├── check_data_integrity.sh         # Shell wrapper for Oracle data check
├── check_data_integrity.sql        # Oracle SQL data comparison script
├── check_csv_integrity.sh          # CSV comparison script
├── check_excel_integrity.py        # Excel comparison script
├── check_schema_integrity.sh       # Shell wrapper for Oracle schema check
├── export_schema_objects.sql       # Oracle SQL schema object export script
├── export_table_to_csv.sql         # Oracle SQL table export script
├── config/                         # Configuration files
│   ├── test_config.csv             # Test case definitions (runner)
│   ├── env_test_cases.csv          # Test case definitions (env check)
│   └── db_config.conf              # DB connection config (schema check)
├── test_scripts/                   # Pre-test helper scripts
│   ├── test1.sh
│   └── test_script2.sh
├── test_input/                     # Input data for test cases
│   └── test01.csv
├── test_csv/                       # Sample CSV test data
│   ├── source.csv
│   └── target.csv
├── test_excel/                     # Sample Excel test data
│   ├── source.xlsx
│   └── target.xlsx
├── logs/                           # Test output logs + summary + reports
└── wheel/                          # Pre-downloaded .whl files
```

---

## Troubleshooting

### Data Integrity SQL Script

| Issue | Solution |
|-------|----------|
| sqlcl not found | Update `SQLCL_PATH` in `check_data_integrity.sh` or `brew install --cask sqlcl` |
| ORA-00942: table not found | Check schema/table names and permissions |
| Large object errors | BLOB/CLOB columns are automatically excluded |

### Schema Integrity Script

| Issue | Solution |
|-------|----------|
| sqlcl/sqlplus not found | Set `DB_CLI_TOOL`, `SQLCL_PATH`, or `SQLPLUS_PATH` in `config/db_config.conf` |
| No objects exported | Verify schema name and read access to `ALL_*` dictionary views |
| Object definitions differ but seem the same | Check for whitespace/case differences in source code or view text |
| Very long view text exceeds line length | View text is normalized (newlines → spaces) in the fingerprint |
| `FAIL: Objects valid in SOURCE but invalid in TARGET` | Check target schema for compilation errors (missing dependencies, invalid references). The object compiles in source but not in target. |
| `WARNING: Objects invalid in SOURCE but valid in TARGET` | Source schema has compilation issues that have been fixed in target. Investigate source. |
| `WARNING: Objects invalid in BOTH schemas` | Same object is broken in both schemas. Usually a shared dependency issue. |

### CSV Script

| Issue | Solution |
|-------|----------|
| Permission denied | `chmod +x check_csv_integrity.sh` |
| Column count mismatch | Verify both CSV files have the same structure |
| Empty values not matching | Empty values are normalized to "NULL" |

### Excel Script

| Issue | Solution |
|-------|----------|
| pandas/openpyxl required | `pip3 install pandas openpyxl` |
| Could not read Excel file | Verify file path and format |
| Sheet not found | Sheet names are case-sensitive |

### Environment Check Script

| Issue | Solution |
|-------|----------|
| `env_test_cases.csv` not found | Ensure the file is in `config/env_test_cases.csv` |
| `check_environment.sh` permission denied | `chmod +x check_environment.sh` |
| `stat: illegal option` | This script uses macOS `stat` syntax (`-f %A`). On Linux, change to `stat -c %a` in the `perm` case block. |

---

---

## Related Scripts

### `export_schema_objects.sql`

Standalone SQL script for exporting schema object definitions, including a compilation status check (`INVALID|` prefix for objects with `status = 'INVALID'`). Can be used independently for debugging or custom tooling:

```bash
sqlcl -s user/pass@db @export_schema_objects.sql SCHEMA_NAME > objects.txt
sort -o objects.txt objects.txt
```

---

## License

This project is provided as-is for data integrity checking purposes.
