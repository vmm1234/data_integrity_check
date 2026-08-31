-- ============================================================================
-- SQL*Plus Script: Export Table Data to CSV Format
-- ============================================================================
-- USAGE:
--   sqlplus -s user/pass@db @export_table_to_csv.sql SCHEMA TABLE [PARTITION]
--
-- PARAMETERS:
--   &1 = SCHEMA name
--   &2 = TABLE name
--   &3 = PARTITION name (or NO_PARTITION / empty if none)
--
-- Output is written to stdout. Redirect to file when calling.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET VERIFY OFF
SET ECHO OFF
SET PAGESIZE 0
SET LINESIZE 32767

DECLARE
    v_schema VARCHAR2(100) := UPPER('&1');
    v_table VARCHAR2(100) := UPPER('&2');
    v_partition VARCHAR2(100) := '&3';
    v_table_ref VARCHAR2(300);
    v_sql CLOB;
    v_col_list VARCHAR2(4000);
    v_select_list VARCHAR2(4000);
    v_cur SYS_REFCURSOR;
    v_row VARCHAR2(32767);
BEGIN
    -- Build table reference
    v_table_ref := v_schema || '.' || v_table;
    IF v_partition IS NOT NULL AND v_partition != 'NO_PARTITION' THEN
        v_table_ref := v_table_ref || ' PARTITION (' || v_partition || ')';
    END IF;

    -- Build column list and select list for CSV
    v_col_list := '';
    v_select_list := '';

    FOR c IN (
        SELECT column_name, data_type, column_id
        FROM all_tab_columns
        WHERE owner = v_schema
          AND table_name = v_table
          AND data_type NOT IN ('BLOB', 'CLOB', 'BFILE', 'NCLOB', 'LONG', 'LONG RAW')
        ORDER BY column_id
    ) LOOP
        IF v_col_list IS NOT NULL THEN
            v_col_list := v_col_list || ',';
            v_select_list := v_select_list || ' || '','' || ';
        END IF;

        v_col_list := v_col_list || '"' || c.column_name || '"';

        -- Format based on data type
        IF c.data_type IN ('VARCHAR2', 'CHAR', 'NVARCHAR2', 'NCHAR') THEN
            v_select_list := v_select_list ||
                '''"'' || REPLACE(NVL(' || '"' || c.column_name || '"' || ', ''NULL''), ''"'', ''""'') || ''"''';
        ELSIF c.data_type IN ('DATE', 'TIMESTAMP', 'TIMESTAMP WITH TIME ZONE',
                               'TIMESTAMP WITH LOCAL TIME ZONE', 'INTERVAL DAY TO SECOND',
                               'INTERVAL YEAR TO MONTH') THEN
            v_select_list := v_select_list ||
                'NVL(TO_CHAR(' || '"' || c.column_name || '"' || ', ''YYYY-MM-DD HH24:MI:SS''), ''NULL'')';
        ELSIF c.data_type IN ('NUMBER', 'FLOAT', 'BINARY_FLOAT', 'BINARY_DOUBLE') THEN
            v_select_list := v_select_list || 'NVL(TO_CHAR(' || '"' || c.column_name || '"' || '), ''NULL'')';
        ELSE
            v_select_list := v_select_list || 'NVL(TO_CHAR(' || '"' || c.column_name || '"' || '), ''NULL'')';
        END IF;
    END LOOP;

    IF v_col_list IS NULL THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: No columns found in ' || v_schema || '.' || v_table);
        RETURN;
    END IF;

    -- Print header
    DBMS_OUTPUT.PUT_LINE(v_col_list);

    -- Build data query
    v_sql := 'SELECT ' || v_select_list || ' FROM ' || v_table_ref;

    -- Open cursor and fetch rows
    OPEN v_cur FOR v_sql;
    LOOP
        FETCH v_cur INTO v_row;
        EXIT WHEN v_cur%NOTFOUND;
        DBMS_OUTPUT.PUT_LINE(v_row);
    END LOOP;
    CLOSE v_cur;

EXCEPTION
    WHEN OTHERS THEN
        IF v_cur%ISOPEN THEN
            CLOSE v_cur;
        END IF;
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('SQL: ' || v_sql);
END;
/

EXIT;