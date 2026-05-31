DECLARE @BlockType NVARCHAR(50) = 'task';

IF OBJECT_ID('tempdb..#ParsedXml')  IS NOT NULL DROP TABLE #ParsedXml;
IF OBJECT_ID('tempdb..#Blocks')     IS NOT NULL DROP TABLE #Blocks;
IF OBJECT_ID('tempdb..#FilteredQA') IS NOT NULL DROP TABLE #FilteredQA;

-- Step 1: Convert workflow Details to XML for form workflows only
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
WHERE wt.Name LIKE '%form';

-- Step 2: Shred XML and filter to matching BlockType only
SELECT DISTINCT
    pw.WorkflowName,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    q.qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)') AS QAID
INTO #Blocks
FROM #ParsedXml pw
CROSS APPLY pw.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop)
WHERE LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) LIKE '%' + @BlockType + '%';

-- Step 3: Get Quick Actions for matched blocks and extract team name
SELECT
    qa.Id,
    qa.Definition,
    CHARINDEX('"ExpressionText":"', qa.Definition,
        CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)) + 18 AS ValStart
INTO #FilteredQA
FROM frs_def_quick_actions qa
WHERE CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition) > 0
  AND EXISTS (
      SELECT 1 FROM #Blocks b
      WHERE TRY_CAST(b.QAID AS uniqueidentifier) = qa.Id
  );

-- Final result: all static teams using the specified BlockType (dynamic expressions excluded)
SELECT DISTINCT
    LEFT(
        SUBSTRING(qa.Definition, qa.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, qa.ValStart, 500)) - 1
    ) AS TeamName,
    b.WorkflowName,
    b.BlockTitle,
    b.BlockType
FROM #Blocks b
JOIN #FilteredQA qa ON qa.Id = TRY_CAST(b.QAID AS uniqueidentifier)
WHERE LEFT(
        SUBSTRING(qa.Definition, qa.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, qa.ValStart, 500)) - 1
    ) <> ''
  AND LEFT(
        SUBSTRING(qa.Definition, qa.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, qa.ValStart, 500)) - 1
    ) NOT LIKE '$(%'
ORDER BY TeamName, WorkflowName;

-- Cleanup
DROP TABLE #ParsedXml;
DROP TABLE #Blocks;
DROP TABLE #FilteredQA;
