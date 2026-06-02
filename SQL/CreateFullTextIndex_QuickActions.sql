-- Verify full-text search is installed (must return 1 before proceeding)
SELECT FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') AS IsInstalled;

-- Find the actual primary key name on the table
SELECT name AS PrimaryKeyName
FROM sys.indexes
WHERE object_id = OBJECT_ID('frs_def_quick_actions')
  AND is_primary_key = 1;

-- Create the full-text catalog
IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_catalogs
    WHERE name = 'FTCatalog_QuickActions'
)
CREATE FULLTEXT CATALOG FTCatalog_QuickActions;

-- Create the full-text index on Definition
-- Replace PK_frs_def_quick_actions with the actual PK name from the query above
IF NOT EXISTS (
    SELECT 1 FROM sys.fulltext_indexes
    WHERE object_id = OBJECT_ID('frs_def_quick_actions')
)
CREATE FULLTEXT INDEX ON frs_def_quick_actions (Definition)
    KEY INDEX PK_frs_def_quick_actions
    ON FTCatalog_QuickActions
    WITH CHANGE_TRACKING AUTO;
