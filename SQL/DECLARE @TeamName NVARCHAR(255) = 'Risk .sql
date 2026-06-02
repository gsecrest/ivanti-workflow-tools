DECLARE @TeamName NVARCHAR(255) = 'Risk Management Support';

-- Cleanup from any previous runs
IF OBJECT_ID('tempdb..#FilteredQA')        IS NOT NULL DROP TABLE #FilteredQA;
IF OBJECT_ID('tempdb..#FilteredWorkflows') IS NOT NULL DROP TABLE #FilteredWorkflows;
IF OBJECT_ID('tempdb..#Blocks')            IS NOT NULL DROP TABLE #Blocks;

-- Step 1: Find matching Quick Actions first (fast string search, no XML)
SELECT
    qa.Id,
    qa.Definition,
    CHARINDEX('"ExpressionText":"', qa.Definition,
        CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)) + 18 AS ValStart
INTO #FilteredQA
FROM frs_def_quick_actions qa
WHERE qa.Definition LIKE '%' + @TeamName + '%'
  AND CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition) > 0;

CREATE UNIQUE CLUSTERED INDEX IX_FilteredQA_Id ON #FilteredQA (Id);

-- Step 2: Pre-filter workflows using raw text search for matching QAIDs
--         Avoids XML parsing the entire table
SELECT
    wt.Name AS WorkflowName,
    CAST(
        REPLACE(REPLACE(CAST(wf.Details AS nvarchar(max)),
            '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
            ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
    AS XML) AS XmlData
INTO #FilteredWorkflows
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type wt
    ON wf.WorkflowTypeLink_RecID = wt.RecID
WHERE wt.Name LIKE '%form'
  AND EXISTS (
      SELECT 1 FROM #FilteredQA fqa
      WHERE CAST(wf.Details AS nvarchar(max)) LIKE '%' + CAST(fqa.Id AS nvarchar(50)) + '%'
  );

-- Step 3: XML shredding only on the small matched set
SELECT DISTINCT
    fw.WorkflowName,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    q.qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)') AS QAID
INTO #Blocks
FROM #FilteredWorkflows fw
CROSS APPLY fw.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop);

-- Step 4: Final result
SELECT DISTINCT
    b.WorkflowName,
    b.BlockTitle,
    b.BlockType,
    LEFT(
        SUBSTRING(qa.Definition, qa.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, qa.ValStart, 500)) - 1
    ) AS TeamName
FROM #Blocks b
JOIN #FilteredQA qa ON qa.Id = TRY_CAST(b.QAID AS uniqueidentifier)
WHERE LEFT(
        SUBSTRING(qa.Definition, qa.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, qa.ValStart, 500)) - 1
    ) <> ''
ORDER BY b.WorkflowName;

-- Cleanup
DROP TABLE #FilteredQA;
DROP TABLE #FilteredWorkflows;
DROP TABLE #Blocks;