# Release Notes

## Version 1.0 (2026-07-16) - Initial Release

### Overview

This is the initial release of the Data Integrity Check Tools, a comprehensive suite for validating data integrity across multiple data sources including Oracle databases, CSV files, and Excel spreadsheets.

---

### New Features

#### 1. Oracle Database Data Integrity Check

**Files:** `check_data_integrity.sql`, `check_data_integrity.sh`

- Set-based comparison using SQL MINUS/INTERSECT operators
- Automatic column discovery from table metadata
- Excludes BLOB/CLOB columns automatically
- Cross-database comparison support
- Color-coded console output
- Detailed mismatch report generation

**Usage:**
```bash
./check_data_integrity.sh SOURCE_SCHEMA SOURCE_TABLE TARGET_SCHEMA TARGET_TABLE
```

---

#### 2. CSV File Comparison

**File:** `check_csv_integrity.sh`

- Sorted diff approach to avoid cascading mismatches from row reordering
- Automatic column discovery from header row
- Color-coded console output with PASS/FAIL indicators
- Column-by-column mismatch details

**Usage:**
```bash
./check_csv_integrity.sh source.csv target.csv
```

---

#### 3. Excel File Comparison

**File:** `check_excel_integrity.py`

- Position-based row-by-row and cell-by-cell comparison
- Multi-sheet support
- Optional HTML report generation
- Verbose mode for detailed cell-level mismatch reporting
- Supports both XLS and XLSX formats

**Prerequisites:** pandas, openpyxl

**Usage:**
```bash
python3 check_excel_integrity.py source.xlsx target.xlsx --verbose
```

---

#### 4. Oracle Schema Integrity Check

**Files:** `check_schema_integrity.sh`, `export_schema_objects.sql`

Compares object definitions between two Oracle schemas on different databases. Supports 13+ object types:

| Object Type | What's Checked |
|-------------|----------------|
| TABLE | Columns (name, type, length, precision, scale, nullable, default) |
| TABLE | Constraints (PK, FK, UNIQUE, CHECK) |
| VIEW | View name and definition |
| PROCEDURE / FUNCTION / PACKAGE / TYPE | Full source code |
| TRIGGER | Name, table, type, event, status |
| SEQUENCE | Min, max, increment, cache, cycle, order |
| INDEX | Uniqueness, type, visibility, columns |
| SYNONYM | Target owner, table name, db_link |
| MATERIALIZED VIEW | Definition |
| DIRECTORY | Directory name and OS path |
| GRANTS | Object privileges, role grants, system privileges |
| All Objects | Compilation status (VALID/INVALID) |

- Fingerprint-based diff using `comm` command
- Compilation status check detects INVALID objects
- Cross-database comparison support
- Color-coded console output with breakdown by object type

**Usage:**
```bash
./check_schema_integrity.sh config/db_config.conf HR_PROD HR_STAGING
```

---

#### 5. Environment Validation

**File:** `check_environment.sh`

Validates the runtime environment with four check types:

| Type | Description |
|------|-------------|
| `exists` | Passes if path exists |
| `not_exists` | Passes if path does NOT exist |
| `perm` | Passes if file permission matches expected octal value |
| `cmd` | Passes if command executes successfully |

- Reads test cases from `config/env_test_cases.csv`
- JUnit/Xray XML report generation
- Color-coded console output

**Usage:**
```bash
./check_environment.sh --output logs/env_report.xml
```

---

#### 6. Test Runner

**File:** `run_check_integrity.sh`

Automates execution of data integrity test cases with advanced features:

- **Multi-Check Test Cases:** Run multiple integrity checks under a single test_id
- **Pre-test Scripts:** Execute setup scripts before test execution
- **Negative Test Cases:** Mark tests where data should differ (`expected_result=FAIL`)
- **Xray Integration:** Maps to Xray XML properties (test_key, requirement)
- **Blocked Cases:** Skip tests with `blocked_case_flag=Y`
- **Output:** JUnit XML report, CSV summary, per-test logs

**Test Configuration:** `config/test_config.csv`

**Usage:**
```bash
./run_check_integrity.sh
```

---

### Offline Support

Pre-downloaded wheel files for Python dependencies:

| Package | Purpose |
|---------|---------|
| pandas | DataFrame comparison engine |
| openpyxl | XLSX file reader |
| numpy | pandas dependency |
| python-dateutil | pandas dependency |
| pytz | pandas timezone support |
| six | python-dateutil compatibility |
| tzdata | IANA timezone data |
| et-xmlfile | openpyxl dependency |

**Setup for offline environments:**
```bash
python3 -m venv venv
source venv/bin/activate
python3 -m pip install --no-index --find-links wheel/ -r requirements.txt
```

---

### Test Data

Sample test data included for validation:

- **CSV:** `test_csv/source.csv`, `test_csv/target.csv` (20 rows each)
- **Excel:** `test_excel/source.xlsx`, `test_excel/target.xlsx` (20 rows each)
- **Test Config:** `config/test_config.csv` (6 test cases)
- **Env Test Cases:** `config/env_test_cases.csv` (8 environment checks)

---

### Project Structure

```
data_integrity_check/
├── README.md                       # Main documentation
├── RELEASE_NOTES.md                # This file
├── requirements.txt                # Python dependencies
├── run_check_integrity.sh          # Test runner
├── check_environment.sh            # Environment validation
├── check_data_integrity.sh         # Oracle data check wrapper
├── check_data_integrity.sql        # Oracle SQL data comparison
├── check_csv_integrity.sh          # CSV comparison
├── check_excel_integrity.py        # Excel comparison
├── check_schema_integrity.sh       # Oracle schema check wrapper
├── export_schema_objects.sql       # Schema object export
├── export_table_to_csv.sql         # Table export to CSV
├── config/                         # Configuration files
│   ├── test_config.csv             # Test case definitions
│   ├── env_test_cases.csv          # Environment test cases
│   └── db_config.conf              # DB connection config
├── test_scripts/                   # Pre-test helper scripts
├── test_input/                     # Input data for tests
├── test_csv/                       # Sample CSV test data
├── test_excel/                     # Sample Excel test data
├── logs/                           # Test output logs
└── wheel/                          # Pre-downloaded .whl files
```

---

### Known Limitations

1. **Excel Comparison:** Position-based comparison may produce cascading mismatches when rows are added/deleted
2. **Oracle Scripts:** Require SQLcl or SQL*Plus installed
3. **CSV Script:** Requires Bash shell and standard Unix tools
4. **Environment Check:** Uses macOS `stat` syntax; may need modification for Linux

---

### Requirements

#### System Requirements

- **Shell Scripts:** Bash shell, standard Unix tools (awk, sort, comm, stat)
- **Excel Scripts:** Python 3.6+, pandas, openpyxl
- **Oracle Scripts:** Oracle Database access, SQLcl or SQL*Plus

#### Database Permissions

- Read permissions on source and target tables
- Read access to `ALL_*` dictionary views
- DBA privilege for `DBA_*` views (schema check)
- SELECT privilege on `V$PARAMETER`

---

### Support

For issues or questions, please refer to the troubleshooting section in `README.md`.