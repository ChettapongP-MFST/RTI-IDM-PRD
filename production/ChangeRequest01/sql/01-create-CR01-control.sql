-- Dedicated CR01 state. Existing ProcessedFiles schema and procedures are unchanged.
-- These tables are NOT mutexes. The controller acquires CR01_ControllerLock in KQL first.
IF OBJECT_ID('dbo.CR01ControllerRun', 'U') IS NULL
CREATE TABLE dbo.CR01ControllerRun (
    RunId VARCHAR(64) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL
);

IF OBJECT_ID('dbo.CR01RefreshRun', 'U') IS NULL
CREATE TABLE dbo.CR01RefreshRun (
    RefreshDate DATE NOT NULL,
    ControllerRunId VARCHAR(64) NOT NULL,
    Status VARCHAR(20) NOT NULL,
    Stage VARCHAR(64) NOT NULL,
    StartedAtUtc DATETIME2(3) NOT NULL,
    CompletedAtUtc DATETIME2(3) NULL
);

IF OBJECT_ID('dbo.CR01RefreshManifest', 'U') IS NULL
CREATE TABLE dbo.CR01RefreshManifest (
    RefreshDate DATE NOT NULL,
    FileName VARCHAR(260) NOT NULL,
    SourceBytes BIGINT NULL,
    SourceLastModified DATETIME2(6) NULL,
    ExpectedRows BIGINT NULL
);

IF OBJECT_ID('dbo.CR01AuditBefore', 'U') IS NULL
CREATE TABLE dbo.CR01AuditBefore (
    RefreshDate DATE NOT NULL,
    FileName VARCHAR(260) NOT NULL,
    IngestedAtUtc DATETIME2(3) NOT NULL,
    RowCount_ BIGINT NOT NULL,
    Status VARCHAR(32) NOT NULL,
    PipelineName VARCHAR(200) NULL,
    PipelineRunId VARCHAR(64) NULL,
    RunAsUser VARCHAR(200) NULL,
    ErrorMsg VARCHAR(4000) NULL
);
