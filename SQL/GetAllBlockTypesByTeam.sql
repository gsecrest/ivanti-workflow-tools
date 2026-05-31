IF OBJECT_ID('tempdb..#AllQA')      IS NOT NULL DROP TABLE #AllQA;
IF OBJECT_ID('tempdb..#ParsedXml')  IS NOT NULL DROP TABLE #ParsedXml;
IF OBJECT_ID('tempdb..#QABlocks')   IS NOT NULL DROP TABLE #QABlocks;
IF OBJECT_ID('tempdb..#TaskBlocks') IS NOT NULL DROP TABLE #TaskBlocks;

-- =============================================
-- PATH 1: QuickAction-based blocks
-- =============================================

-- Step 1: Extract team name from all Quick Actions that have an OwnerTeam set
SELECT
    qa.Id,
    LEFT(
        SUBSTRING(qa.Definition, pos.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, pos.ValStart, 500)) - 1
    ) AS TeamName
INTO #AllQA
FROM frs_def_quick_actions qa
CROSS APPLY (
    SELECT CHARINDEX('"ExpressionText":"', qa.Definition,
        CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)) + 18
) pos(ValStart)
WHERE CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition) > 0
  AND LEFT(
        SUBSTRING(qa.Definition, pos.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, pos.ValStart, 500)) - 1
    ) <> ''
  AND LEFT(
        SUBSTRING(qa.Definition, pos.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, pos.ValStart, 500)) - 1
    ) NOT LIKE '$(%';

CREATE UNIQUE CLUSTERED INDEX IX_AllQA_Id ON #AllQA (Id);

-- Step 2: Parse XML for all form workflows
SELECT
    wt.Name AS WorkflowName,
    CAST(
        REPLACE(REPLACE(CAST(wf.Details AS nvarchar(max)),
            '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
            ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
    AS XML) AS XmlData
INTO #ParsedXml
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type wt
    ON wf.WorkflowTypeLink_RecID = wt.RecID
WHERE wt.Name LIKE '%form'
  AND EXISTS (
      SELECT 1 FROM #AllQA qa
      WHERE CAST(wf.Details AS nvarchar(max)) LIKE '%' + CAST(qa.Id AS nvarchar(50)) + '%'
  );

-- Step 3: Shred XML and join to Quick Actions to get team
SELECT DISTINCT
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    qa.TeamName
INTO #QABlocks
FROM #ParsedXml pw
CROSS APPLY pw.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop)
JOIN #AllQA qa
    ON qa.Id = TRY_CAST(q.qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)') AS uniqueidentifier);

-- =============================================
-- PATH 2: Task blocks (teamblock property)
-- =============================================

SELECT DISTINCT
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
  AND LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) <> ''
  AND LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) NOT LIKE '$(%';

-- =============================================
-- Final result: all block types with a team assigned
-- =============================================
SELECT
    BlockType,
    TeamName,
    COUNT(*) AS BlockCount
FROM (
    SELECT BlockType, TeamName FROM #QABlocks
    UNION ALL
    SELECT BlockType, TeamName FROM #TaskBlocks
) Combined
GROUP BY BlockType, TeamName
ORDER BY BlockType, TeamName;

-- Cleanup
DROP TABLE #AllQA;
DROP TABLE #ParsedXml;
DROP TABLE #QABlocks;
DROP TABLE #TaskBlocks;
