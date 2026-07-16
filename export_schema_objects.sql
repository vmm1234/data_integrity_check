-- ============================================================================
-- SQL*Plus/SQLcl Script: Export Schema Object Definitions to Comparable Format
-- ============================================================================
-- USAGE:
--   sqlcl  -s user/pass@db @export_schema_objects.sql SCHEMA_NAME
--   sqlplus -s user/pass@db @export_schema_objects.sql SCHEMA_NAME
--
-- PARAMETERS:
--   &1 = SCHEMA_NAME (e.g. HR)
--
-- OUTPUT:
--   Pipe-delimited fingerprint lines to stdout, one per object detail.
--   Lines are prefixed with type markers for sorted group comparison:
--     TAB_COL    - Table column definition
--     CONSTR     - Table constraint
--     VIEW       - View text (normalized)
--     SRC        - Source code line (PROCEDURE, FUNCTION, PACKAGE, etc.)
--     TRIG       - Trigger definition
--     SEQ        - Sequence definition
--     IDX        - Index definition
--     SYN        - Synonym definition
--     MVIEW      - Materialized view query (normalized)
--     DIR        - Directory object path (DBA_DIRECTORIES)
--     GRANT_OBJ  - Object-level grant (DBA_TAB_PRIVS)
--     GRANT_ROLE - Role grant (DBA_ROLE_PRIVS)
--     GRANT_SYS  - System privilege (DBA_SYS_PRIVS)
--     PARAM      - Database parameter (V$PARAMETER)
--
--   Redirect output to a file, then sort it before comparing.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET VERIFY OFF
SET ECHO OFF
SET PAGESIZE 0
SET LINESIZE 32767
SET LONG 10000000
SET LONGCHUNKSIZE 10000000
SET TRIMSPOOL ON
SET TRIMOUT ON

DEFINE SCHEMA_NAME = '&1'

DECLARE
    v_schema VARCHAR2(100) := UPPER('&SCHEMA_NAME');

    PROCEDURE p(line VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(line);
    END;

BEGIN
    -- ==========================================================================
    -- 1. TABLE COLUMNS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'TAB_COL|' ||
            owner || '|' ||
            table_name || '|' ||
            column_name || '|' ||
            data_type || '|' ||
            NVL(TO_CHAR(data_length), '') || '|' ||
            NVL(TO_CHAR(data_precision), '') || '|' ||
            NVL(TO_CHAR(data_scale), '') || '|' ||
            nullable AS line
        FROM all_tab_columns
        WHERE owner = v_schema
          AND data_type NOT IN ('BLOB','CLOB','BFILE','NCLOB','LONG','LONG RAW')
        ORDER BY table_name, column_id
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 2. TABLE CONSTRAINTS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'CONSTR|' ||
            c.owner || '|' ||
            c.table_name || '|' ||
            c.constraint_name || '|' ||
            c.constraint_type || '|' ||
            NVL((SELECT LISTAGG(cc.column_name, ',') WITHIN GROUP (ORDER BY cc.position)
                 FROM all_cons_columns cc
                 WHERE cc.owner = c.owner
                   AND cc.constraint_name = c.constraint_name
                   AND cc.table_name = c.table_name), '') || '|' ||
            NVL(c.r_owner, '') || '|' ||
            NVL(c.r_constraint_name, '') AS line
        FROM all_constraints c
        WHERE c.owner = v_schema
        ORDER BY c.table_name, c.constraint_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 3. VIEWS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'VIEW|' ||
            owner || '|' ||
            view_name AS line
        FROM all_views
        WHERE owner = v_schema
        ORDER BY view_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 4. PROCEDURES, FUNCTIONS, PACKAGES, TYPES (source code)
    -- ==========================================================================
    FOR r IN (
        SELECT
            'SRC|' ||
            owner || '|' ||
            type || '|' ||
            name || '|' ||
            LPAD(TO_CHAR(line), 6, '0') || '|' ||
            text AS line
        FROM all_source
        WHERE owner = v_schema
          AND type IN ('PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE BODY', 'TYPE', 'TYPE BODY')
        ORDER BY name, type, line
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 5. TRIGGERS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'TRIG|' ||
            owner || '|' ||
            trigger_name || '|' ||
            table_owner || '|' ||
            table_name || '|' ||
            trigger_type || '|' ||
            triggering_event || '|' ||
            status AS line
        FROM all_triggers
        WHERE owner = v_schema
        ORDER BY trigger_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 6. SEQUENCES
    -- ==========================================================================
    FOR r IN (
        SELECT
            'SEQ|' ||
            sequence_owner || '|' ||
            sequence_name || '|' ||
            NVL(TO_CHAR(min_value), '') || '|' ||
            NVL(TO_CHAR(max_value), '') || '|' ||
            NVL(TO_CHAR(increment_by), '') || '|' ||
            NVL(TO_CHAR(cache_size), '') || '|' ||
            cycle_flag || '|' ||
            order_flag AS line
        FROM all_sequences
        WHERE sequence_owner = v_schema
        ORDER BY sequence_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 7. INDEXES
    -- ==========================================================================
    FOR r IN (
        SELECT
            'IDX|' ||
            i.owner || '|' ||
            i.table_name || '|' ||
            i.index_name || '|' ||
            i.uniqueness || '|' ||
            i.index_type || '|' ||
            i.visibility || '|' ||
            NVL((SELECT LISTAGG(c.column_name, ',') WITHIN GROUP (ORDER BY c.column_position)
                 FROM all_ind_columns c
                 WHERE c.index_owner = i.owner
                   AND c.index_name = i.index_name
                   AND c.table_name = i.table_name), '') AS line
        FROM all_indexes i
        WHERE i.owner = v_schema
          AND i.table_type = 'TABLE'
        ORDER BY i.table_name, i.index_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 8. SYNONYMS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'SYN|' ||
            owner || '|' ||
            synonym_name || '|' ||
            table_owner || '|' ||
            table_name || '|' ||
            NVL(db_link, '') AS line
        FROM all_synonyms
        WHERE owner = v_schema
        ORDER BY synonym_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 9. MATERIALIZED VIEWS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'MVIEW|' ||
            owner || '|' ||
            mview_name AS line
        FROM all_mviews
        WHERE owner = v_schema
        ORDER BY mview_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 10. DIRECTORIES
    -- ==========================================================================
    FOR r IN (
        SELECT
            'DIR|' ||
            directory_name || '|' ||
            directory_path AS line
        FROM dba_directories
        ORDER BY directory_name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 11. OBJECT-LEVEL GRANTS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'GRANT_OBJ|' ||
            grantee || '|' ||
            owner || '|' ||
            table_name || '|' ||
            privilege || '|' ||
            grantable AS line
        FROM dba_tab_privs
        WHERE grantee = v_schema
        ORDER BY owner, table_name, privilege
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 12. ROLE GRANTS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'GRANT_ROLE|' ||
            grantee || '|' ||
            granted_role || '|' ||
            admin_option AS line
        FROM dba_role_privs
        WHERE grantee = v_schema
        ORDER BY granted_role
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 13. SYSTEM PRIVILEGES
    -- ==========================================================================
    FOR r IN (
        SELECT
            'GRANT_SYS|' ||
            grantee || '|' ||
            privilege || '|' ||
            admin_option AS line
        FROM dba_sys_privs
        WHERE grantee = v_schema
        ORDER BY privilege
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 14. DATABASE PARAMETERS
    -- ==========================================================================
    FOR r IN (
        SELECT
            'PARAM|' ||
            name || '|' ||
            NVL(value, 'NULL') || '|' ||
            isdefault AS line
        FROM v$parameter
        WHERE ispdb = 'NO'
        ORDER BY name
    ) LOOP
        p(r.line);
    END LOOP;

    -- ==========================================================================
    -- 15. INVALID OBJECTS (compilation status check)
    -- ==========================================================================
    FOR r IN (
        SELECT
            'INVALID|' ||
            owner || '|' ||
            object_type || '|' ||
            object_name || '|' ||
            status AS line
        FROM all_objects
        WHERE owner = v_schema
          AND object_type IN ('PROCEDURE', 'FUNCTION', 'PACKAGE', 'PACKAGE BODY',
                              'TYPE', 'TYPE BODY', 'VIEW', 'MATERIALIZED VIEW',
                              'TRIGGER')
          AND status = 'INVALID'
        ORDER BY object_type, object_name
    ) LOOP
        p(r.line);
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END;
/
EXIT;
