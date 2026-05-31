DECLARE @TeamName  NVARCHAR(255) = 'Risk Management Support';
DECLARE @BlockType NVARCHAR(50)  = '';  -- e.g. 'task', 'advancedtask', leave blank to return all

IF OBJECT_ID('tempdb..#FilteredQA')        IS NOT NULL DROP TABLE #FilteredQA;
IF OBJECT_ID('tempdb..#FilteredWorkflows') IS NOT NULL DROP TABLE #FilteredWorkflows;
IF OBJECT_ID('tempdb..#Blocks')            IS NOT NULL DROP TABLE #Blocks;
IF OBJECT_ID('tempdb..#TaskBlocks')        IS NOT NULL DROP TABLE #TaskBlocks;

-- =============================================
-- PATH 1: QuickAction-based blocks (e.g. advancedtask)
-- =============================================

-- Step 1: Find matching Quick Actions (switch LIKE to CONTAINS once full-text index is created)
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

-- Step 3: Shred XML for QuickAction blocks
SELECT DISTINCT
    fw.WorkflowName,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    q.qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)') AS QAID
INTO #Blocks
FROM #FilteredWorkflows fw
CROSS APPLY fw.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop);

-- =============================================
-- PATH 2: Task blocks (team stored in teamblock property)
-- =============================================

SELECT DISTINCT
    wt.Name AS WorkflowName,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    LTRIM(RTRIM(p.prop.value('(value)[1]',  'nvarchar(255)'))) AS TeamName
INTO #TaskBlocks
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type wt
    ON wf.WorkflowTypeLink_RecID = wt.RecID
CROSS APPLY (
    SELECT CAST(
        REPLACE(REPLACE(CAST(wf.Details AS nvarchar(max)),
            '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
            ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
    AS XML) AS XmlData
) x
CROSS APPLY x.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="teamblock"]/groups/group/param[name="team"]') p(prop)
WHERE wt.Name LIKE '%form'
  AND LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) LIKE '%' + @TeamName + '%'
  AND LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) <> ''
  AND LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) NOT LIKE '$(%'
  AND (@BlockType = '' OR LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) LIKE '%' + @BlockType + '%');

-- =============================================
-- Final result: UNION both paths
-- =============================================
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
  AND (@BlockType = '' OR b.BlockType LIKE '%' + @BlockType + '%')

UNION ALL

SELECT DISTINCT
    WorkflowName,
    BlockTitle,
    BlockType,
    TeamName
FROM #TaskBlocks

ORDER BY WorkflowName;

-- Cleanup
DROP TABLE #FilteredQA;
DROP TABLE #FilteredWorkflows;
DROP TABLE #Blocks;
DROP TABLE #TaskBlocks;
