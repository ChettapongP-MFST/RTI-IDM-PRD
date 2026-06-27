-- Production 02 — Create ProcessedFiles audit/control table
-- Target: Fabric Warehouse "wh_control_framework"
-- Run in the Warehouse SQL query editor (New SQL query)
--
-- Purpose: deduplication + audit log for the event-driven Data Pipeline.
-- Before ingesting a file, the pipeline checks this table; after copy, it
-- writes one row recording the outcome (Success / Failed / Skipped-Duplicate).

----------------------------------------------------------------------
-- 1. Create the control table (idempotent)
----------------------------------------------------------------------
IF OBJECT_ID('dbo.ProcessedFiles', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProcessedFiles (
        FileName      VARCHAR(260)  NOT NULL,   -- natural key for dedup (blob path / file name)
        IngestedAtUtc DATETIME2(3)  NOT NULL,   -- when this row was written
        RowCount_     BIGINT        NOT NULL,   -- rows copied (trailing _: ROWCOUNT is reserved in T-SQL)
        Status        VARCHAR(32)   NOT NULL,   -- Success | Failed | Skipped-Duplicate
        PipelineName  VARCHAR(200)  NULL,       -- @pipeline().Pipeline
        PipelineRunId VARCHAR(64)   NULL,       -- @pipeline().RunId
        RunAsUser     VARCHAR(200)  NULL,       -- trigger type + name
        ErrorMsg      VARCHAR(4000) NULL        -- Copy Activity error (if any)
    );
END;
GO

----------------------------------------------------------------------
-- 2. (Optional) Upsert stored procedure used by the pipeline
--    The pipeline calls this from a Script / Stored procedure activity
--    after each Copy. Keeps the pipeline JSON clean and the merge logic
--    in one versioned place.
----------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_LogProcessedFile
    @FileName      VARCHAR(260),
    @RowCount      BIGINT,
    @Status        VARCHAR(32),
    @PipelineName  VARCHAR(200) = NULL,
    @PipelineRunId VARCHAR(64)  = NULL,
    @RunAsUser     VARCHAR(200) = NULL,
    @ErrorMsg      VARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ProcessedFiles
        (FileName, IngestedAtUtc, RowCount_, Status, PipelineName, PipelineRunId, RunAsUser, ErrorMsg)
    VALUES
        (@FileName, SYSUTCDATETIME(), @RowCount, @Status, @PipelineName, @PipelineRunId, @RunAsUser, @ErrorMsg);
END;
GO

----------------------------------------------------------------------
-- Helpful read patterns (uncomment to use)
----------------------------------------------------------------------
-- SELECT Status, COUNT(*) AS Files, SUM(RowCount_) AS Rows_
-- FROM dbo.ProcessedFiles
-- GROUP BY Status;

-- Has a given file already been processed successfully?
-- SELECT COUNT(*) AS AlreadyDone
-- FROM dbo.ProcessedFiles
-- WHERE FileName = 'inbound/statement/INTRADAY_SUMMARY_20260615_0945_1000.CSV'
--   AND Status = 'Success';
