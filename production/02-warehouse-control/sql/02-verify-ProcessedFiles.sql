-- Production 02 — Verification Script
-- Run in the Fabric Warehouse "wh_control_framework" after running 01-create-ProcessedFiles.sql
-- These queries confirm the control table and helper procedure were created correctly.

-- ============================================================================
-- 1. Confirm the table exists
-- ============================================================================
-- Expected: 1 row (schema_name = dbo, table_name = ProcessedFiles)
SELECT  s.name AS SchemaName,
        t.name AS TableName
FROM    sys.tables t
JOIN    sys.schemas s ON s.schema_id = t.schema_id
WHERE   t.name = 'ProcessedFiles';

-- ============================================================================
-- 2. Confirm the column schema (8 columns)
-- ============================================================================
-- Expected: 8 rows with the correct names / types / nullability
SELECT  c.column_id        AS Ordinal,
        c.name             AS ColumnName,
        ty.name            AS DataType,
        c.max_length       AS MaxLength,
        c.is_nullable      AS IsNullable
FROM    sys.columns c
JOIN    sys.types   ty ON ty.user_type_id = c.user_type_id
WHERE   c.object_id = OBJECT_ID('dbo.ProcessedFiles')
ORDER BY c.column_id;

-- ============================================================================
-- 3. Confirm the helper stored procedure exists
-- ============================================================================
-- Expected: 1 row (usp_LogProcessedFile)
SELECT  name AS ProcedureName,
        create_date,
        modify_date
FROM    sys.procedures
WHERE   name = 'usp_LogProcessedFile';

-- ============================================================================
-- 4. Confirm the table is empty and ready
-- ============================================================================
-- Expected: 0 rows (awaiting pipeline writes)
SELECT COUNT(*) AS Rows_ FROM dbo.ProcessedFiles;

-- ============================================================================
-- 5. (Optional) Smoke-test the logging procedure, then clean up
-- ============================================================================
-- Uncomment to insert one test row, read it back, then delete it.
-- EXEC dbo.usp_LogProcessedFile
--      @FileName      = 'TEST/smoke_test.CSV',
--      @RowCount      = 0,
--      @Status        = 'Success',
--      @PipelineName  = 'manual-verify',
--      @PipelineRunId = '00000000-0000-0000-0000-000000000000',
--      @RunAsUser     = 'verify-script',
--      @ErrorMsg      = NULL;
--
-- SELECT * FROM dbo.ProcessedFiles WHERE FileName = 'TEST/smoke_test.CSV';
--
-- DELETE FROM dbo.ProcessedFiles WHERE FileName = 'TEST/smoke_test.CSV';
