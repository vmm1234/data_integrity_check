-- ============================================================================
-- Oracle SQL Script: Data Integrity Check Between Two Tables
-- ============================================================================
-- USAGE:
--   sqlcl user/pass@db @check_data_integrity.sql SOURCE_SCHEMA SOURCE_TABLE TARGET_SCHEMA TARGET_TABLE [SOURCE_PARTITION] [TARGET_PARTITION]
--
-- EXAMPLES:
--   sqlcl test/1234@localhost:1521/xe @check_data_integrity.sql TEST USERS TEST USERS2
--   sqlcl test/1234@localhost:1521/xe @check_data_integrity.sql TEST USERS TEST USERS2 P_EAST P_EAST
--
-- Output written to data_integrity_report.txt in the current directory.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG 1000000
SET LONGCHUNKSIZE 1000000
SET LINESIZE 32767
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET ECHO OFF
SET HEADING OFF
SET TRIMSPOOL ON
SET TRIMOUT ON
SET TERMOUT ON

-- ============================================================================
-- Parameters from shell: &1=SOURCE_SCHEMA, &2=SOURCE_TABLE, &3=TARGET_SCHEMA, &4=TARGET_TABLE, &5=SOURCE_PARTITION (optional), &6=TARGET_PARTITION (optional)
-- ============================================================================
DEFINE SOURCE_SCHEMA = '&1'
DEFINE SOURCE_TABLE = '&2'
DEFINE TARGET_SCHEMA = '&3'
DEFINE TARGET_TABLE = '&4'
DEFINE SOURCE_PARTITION = '&5'
DEFINE TARGET_PARTITION = '&6'
-- ============================================================================

SPOOL data_integrity_report.txt

BEGIN
    EXECUTE IMMEDIATE 'DROP FUNCTION run_data_integrity_check';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TYPE report_lines_t';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TYPE report_line_t';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE OR REPLACE TYPE report_line_t AS OBJECT (line_text VARCHAR2(4000));
/
CREATE OR REPLACE TYPE report_lines_t AS TABLE OF report_line_t;
/

CREATE OR REPLACE FUNCTION run_data_integrity_check(
    p_source_schema IN VARCHAR2,
    p_source_table  IN VARCHAR2,
    p_target_schema IN VARCHAR2,
    p_target_table  IN VARCHAR2,
    p_source_partition IN VARCHAR2 DEFAULT NULL,
    p_target_partition IN VARCHAR2 DEFAULT NULL
) RETURN report_lines_t PIPELINED IS
    v_sel_src VARCHAR2(4000) := '';
    v_sel_tgt VARCHAR2(4000) := '';
    v_col_list VARCHAR2(4000) := '';
    v_join_cond VARCHAR2(4000) := '';
    v_where_cond VARCHAR2(4000) := '';
    v_out_list VARCHAR2(4000) := '';
    v_output_list VARCHAR2(4000) := '';
    v_first_col VARCHAR2(100);
    v_s_cols VARCHAR2(4000);
    v_t_cols VARCHAR2(4000);
    v_sql VARCHAR2(32767);
    v_cnt NUMBER;
    v_source_count NUMBER;
    v_target_count NUMBER;
    v_source_only_count NUMBER;
    v_target_only_count NUMBER;
    v_lines SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();
    v_col_count NUMBER := 0;
    v_source_table_ref VARCHAR2(200);
    v_target_table_ref VARCHAR2(200);
BEGIN
    -- Build table references with optional partition clause
    v_source_table_ref := p_source_schema || '.' || p_source_table ||
        CASE WHEN p_source_partition IS NOT NULL THEN ' PARTITION (' || p_source_partition || ')' END;
    v_target_table_ref := p_target_schema || '.' || p_target_table ||
        CASE WHEN p_target_partition IS NOT NULL THEN ' PARTITION (' || p_target_partition || ')' END;

    -- Validate target table exists and has matching columns
    FOR c IN (
        SELECT column_name FROM all_tab_columns
        WHERE owner = UPPER(p_source_schema) AND table_name = UPPER(p_source_table)
        AND data_type NOT IN ('BLOB','CLOB','BFILE','NCLOB','LONG','LONG RAW')
        ORDER BY column_id
    ) LOOP
        v_col_count := v_col_count + 1;
        IF v_col_count = 1 THEN
            v_first_col := c.column_name;
        END IF;

        -- Check target table has this column
        SELECT COUNT(*) INTO v_cnt FROM all_tab_columns
        WHERE owner = UPPER(p_target_schema) AND table_name = UPPER(p_target_table)
        AND column_name = c.column_name;
        IF v_cnt = 0 THEN
            PIPE ROW(report_line_t('ERROR: Target table ' || UPPER(p_target_schema) || '.' || UPPER(p_target_table)));
            PIPE ROW(report_line_t('  is missing column: ' || c.column_name));
            PIPE ROW(report_line_t('Both tables must have the same column structure.'));
            RETURN;
        END IF;

        IF v_sel_src IS NOT NULL THEN
            v_sel_src := v_sel_src || ', ';
            v_sel_tgt := v_sel_tgt || ', ';
            v_join_cond := v_join_cond || ' AND ';
            v_where_cond := v_where_cond || ' OR ';
            v_out_list := v_out_list || ' || '' | '' || ';
        END IF;

        v_sel_src := v_sel_src || 's.' || c.column_name;
        v_sel_tgt := v_sel_tgt || 't.' || c.column_name;
        v_join_cond := v_join_cond ||
            '(s.' || c.column_name || ' = t.' || c.column_name || ' OR (s.' || c.column_name || ' IS NULL AND t.' || c.column_name || ' IS NULL))';
        v_where_cond := v_where_cond ||
            'NOT (s.' || c.column_name || ' = t.' || c.column_name || ' OR (s.' || c.column_name || ' IS NULL AND t.' || c.column_name || ' IS NULL))';
        v_out_list := v_out_list ||
            'COALESCE(TO_CHAR(s.' || c.column_name || '), ''NULL'') || '' | '' || COALESCE(TO_CHAR(t.' || c.column_name || '), ''NULL'')';
    END LOOP;

    IF v_col_count = 0 THEN
        PIPE ROW(report_line_t('ERROR: No columns found in source table ' || UPPER(p_source_schema) || '.' || UPPER(p_source_table)));
        RETURN;
    END IF;

    v_sel_src := v_sel_src || ', ROW_NUMBER() OVER (ORDER BY s.' || v_first_col || ') AS s_rn';
    v_sel_tgt := v_sel_tgt || ', ROW_NUMBER() OVER (ORDER BY t.' || v_first_col || ') AS t_rn';

    -- Simple column list (no prefixes) for MINUS/INTERSECT
    v_col_list := '';
    FOR c IN (
        SELECT column_name FROM all_tab_columns
        WHERE owner = UPPER(p_source_schema) AND table_name = UPPER(p_source_table)
        AND data_type NOT IN ('BLOB','CLOB','BFILE','NCLOB','LONG','LONG RAW')
        ORDER BY column_id
    ) LOOP
        IF v_col_list IS NOT NULL THEN
            v_col_list := v_col_list || ', ';
        END IF;
        v_col_list := v_col_list || c.column_name;
    END LOOP;

    -- Build simple output list (source columns only, no prefixes)
    v_output_list := '';
    FOR c IN (
        SELECT column_name FROM all_tab_columns
        WHERE owner = UPPER(p_source_schema) AND table_name = UPPER(p_source_table)
        AND data_type NOT IN ('BLOB','CLOB','BFILE','NCLOB','LONG','LONG RAW')
        ORDER BY column_id
    ) LOOP
        IF v_output_list IS NOT NULL THEN
            v_output_list := v_output_list || ' || '' | '' || ';
        END IF;
        v_output_list := v_output_list ||
            'COALESCE(TO_CHAR(' || c.column_name || '), ''NULL'')';
    END LOOP;

    v_s_cols := '';
    v_t_cols := '';
    FOR c IN (
        SELECT column_name FROM all_tab_columns
        WHERE owner = UPPER(p_source_schema) AND table_name = UPPER(p_source_table)
        AND data_type NOT IN ('BLOB','CLOB','BFILE','NCLOB','LONG','LONG RAW')
        ORDER BY column_id
    ) LOOP
        IF v_s_cols IS NOT NULL THEN
            v_s_cols := v_s_cols || ', ';
            v_t_cols := v_t_cols || ', ';
        END IF;
        v_s_cols := v_s_cols || 's.' || c.column_name;
        v_t_cols := v_t_cols || 't.' || c.column_name;
    END LOOP;

    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t('DATA INTEGRITY CHECK REPORT'));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('Source Schema: ' || UPPER(p_source_schema)));
    PIPE ROW(report_line_t('Source Table:  ' || UPPER(p_source_table) || CASE WHEN p_source_partition IS NOT NULL THEN ' PARTITION (' || p_source_partition || ')' END));
    PIPE ROW(report_line_t('Target Schema: ' || UPPER(p_target_schema)));
    PIPE ROW(report_line_t('Target Table:  ' || UPPER(p_target_table) || CASE WHEN p_target_partition IS NOT NULL THEN ' PARTITION (' || p_target_partition || ')' END));
    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t('ROW COUNT SUMMARY'));
    PIPE ROW(report_line_t('============================================================================'));

    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_source_table_ref INTO v_cnt;
    v_source_count := v_cnt;
    PIPE ROW(report_line_t('Source Table Row Count:      ' || v_cnt));

    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_target_table_ref INTO v_cnt;
    v_target_count := v_cnt;
    PIPE ROW(report_line_t('Target Table Row Count:      ' || v_cnt));
    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t('DATA MATCH SUMMARY'));
    PIPE ROW(report_line_t('============================================================================'));

    -- Use MINUS/INTERSECT for efficient comparison (no ROW_NUMBER needed)
    v_sql := 'SELECT COUNT(*) FROM (SELECT ' || v_col_list || ' FROM ' || v_source_table_ref || ' MINUS SELECT ' || v_col_list || ' FROM ' || v_target_table_ref || ')';
    EXECUTE IMMEDIATE v_sql INTO v_cnt;
    v_source_only_count := v_cnt;
    PIPE ROW(report_line_t('Rows in Source Only:         ' || v_cnt));

    v_sql := 'SELECT COUNT(*) FROM (SELECT ' || v_col_list || ' FROM ' || v_target_table_ref || ' MINUS SELECT ' || v_col_list || ' FROM ' || v_source_table_ref || ')';
    EXECUTE IMMEDIATE v_sql INTO v_cnt;
    v_target_only_count := v_cnt;
    PIPE ROW(report_line_t('Rows in Target Only:         ' || v_cnt));

    -- Matching = rows that exist in both tables
    v_sql := 'SELECT COUNT(*) FROM (SELECT ' || v_col_list || ' FROM ' || v_source_table_ref || ' INTERSECT SELECT ' || v_col_list || ' FROM ' || v_target_table_ref || ')';
    EXECUTE IMMEDIATE v_sql INTO v_cnt;
    PIPE ROW(report_line_t('Matching Rows:               ' || v_cnt));

    -- Mismatched: rows that appear in both but with different values
    PIPE ROW(report_line_t('Mismatched Rows:             See details below'));
    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t('DETAILED MISMATCH REPORT'));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('Rows Only in SOURCE Table (up to 100):'));
    PIPE ROW(report_line_t('----------------------------------------'));

    -- Source-only rows: use MINUS to find rows in source but not in target
    v_sql := 'SELECT ''Row #'' || ROWNUM || '': '' || ' || v_output_list || ' FROM (SELECT ' || v_col_list || ' FROM ' || v_source_table_ref || ' MINUS SELECT ' || v_col_list || ' FROM ' || v_target_table_ref || ') WHERE ROWNUM <= 100';
    EXECUTE IMMEDIATE v_sql BULK COLLECT INTO v_lines;
    IF v_lines.COUNT = 0 THEN
        PIPE ROW(report_line_t('No rows found.'));
    ELSE
        FOR i IN 1..v_lines.COUNT LOOP
            PIPE ROW(report_line_t(v_lines(i)));
        END LOOP;
    END IF;

    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('Rows Only in TARGET Table (up to 100):'));
    PIPE ROW(report_line_t('----------------------------------------'));

    v_sql := 'SELECT ''Row #'' || ROWNUM || '': '' || ' || v_output_list || ' FROM (SELECT ' || v_col_list || ' FROM ' || v_target_table_ref || ' MINUS SELECT ' || v_col_list || ' FROM ' || v_source_table_ref || ') WHERE ROWNUM <= 100';
    EXECUTE IMMEDIATE v_sql BULK COLLECT INTO v_lines;
    IF v_lines.COUNT = 0 THEN
        PIPE ROW(report_line_t('No rows found.'));
    ELSE
        FOR i IN 1..v_lines.COUNT LOOP
            PIPE ROW(report_line_t(v_lines(i)));
        END LOOP;
    END IF;

    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t('COLUMN-BY-COLUMN MISMATCH DETAILS'));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t('Note: Shows up to 100 mismatched row comparisons'));
    PIPE ROW(report_line_t(''));

    -- Column-by-column comparison skipped: MINUS already identifies all differences.
    -- Position-based FULL OUTER JOIN causes cascading false mismatches when rows are missing.
    IF v_source_only_count > 0 OR v_target_only_count > 0 THEN
        PIPE ROW(report_line_t('Source-only and target-only rows shown above via MINUS comparison.'));
        PIPE ROW(report_line_t('(Column-by-column skipped: position-based join would show false cascading mismatches)'));
    ELSE
        PIPE ROW(report_line_t('All rows match. No data differences found.'));
    END IF;

    PIPE ROW(report_line_t(''));
    PIPE ROW(report_line_t('============================================================================'));
    PIPE ROW(report_line_t('END OF DATA INTEGRITY CHECK REPORT'));
    PIPE ROW(report_line_t('============================================================================'));

EXCEPTION
    WHEN OTHERS THEN
        PIPE ROW(report_line_t('ERROR: ' || SQLERRM));
        PIPE ROW(report_line_t('SQL: ' || v_sql));
END;
/

SELECT line_text FROM TABLE(run_data_integrity_check('&SOURCE_SCHEMA', '&SOURCE_TABLE', '&TARGET_SCHEMA', '&TARGET_TABLE', '&SOURCE_PARTITION', '&TARGET_PARTITION'));

SPOOL OFF
