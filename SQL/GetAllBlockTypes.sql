IF OBJECT_ID('tempdb..#ParsedXml')  IS NOT NULL DROP TABLE #ParsedXml;
IF OBJECT_ID('tempdb..#Blocks')     IS NOT NULL DROP TABLE #Blocks;
IF OBJECT_ID('tempdb..#BlockTypes') IS NOT NULL DROP TABLE #BlockTypes;

-- Step 1: Convert workflow Details to XML
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

-- Step 2: Shred XML and extract BlockType as a plain column first
SELECT
    LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) AS BlockType
INTO #Blocks
FROM #ParsedXml pw
CROSS APPLY pw.XmlData.nodes('/scenario/blocks/block') b(block);

-- Step 3: Group on the plain column (no XML methods in GROUP BY)
SELECT
    BlockType,
    COUNT(*) AS BlockCount
INTO #BlockTypes
FROM #Blocks
WHERE BlockType <> ''
GROUP BY BlockType;

-- Final result
SELECT
    BlockType,
    BlockCount
FROM #BlockTypes
ORDER BY BlockCount DESC;

-- Cleanup
DROP TABLE #ParsedXml;
DROP TABLE #Blocks;
DROP TABLE #BlockTypes;
