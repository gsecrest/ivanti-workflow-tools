DECLARE @WorkflowName NVARCHAR(255) = '';   -- leave blank to search all workflows
DECLARE @BlockType    NVARCHAR(50)  = '';   -- task, advancedtask, update; leave blank for all
DECLARE @TeamName     NVARCHAR(255) = 'Risk Management Support'; -- leave blank to search all teams
DECLARE @Status       NVARCHAR(50)  = 'Design';   -- e.g. Published, Design; leave blank for all

IF OBJECT_ID('tempdb..#FilteredWorkflows') IS NOT NULL DROP TABLE #FilteredWorkflows;
IF OBJECT_ID('tempdb..#Blocks')            IS NOT NULL DROP TABLE #Blocks;
IF OBJECT_ID('tempdb..#TaskBlocks')        IS NOT NULL DROP TABLE #TaskBlocks;

-- Step 1: Parse XML for most recent version of matching workflows only
SELECT
    wt.Name AS WorkflowName,
    wt.RecID AS WorkflowTypeRecID,
    wf.DefVersion,
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
  AND (@WorkflowName = '' OR wt.Name LIKE '%' + @WorkflowName + '%')
  AND wt.Name NOT LIKE '%backup%'
  AND CAST(wf.DefVersion AS INT) = (
      SELECT MAX(CAST(wf2.DefVersion AS INT))
      FROM frs_def_workflow_definition wf2
      WHERE wf2.WorkflowTypeLink_RecID = wf.WorkflowTypeLink_RecID
  );

-- =============================================
-- PATH 1: QuickAction-based blocks (advancedtask, update)
-- =============================================

SELECT DISTINCT
    fw.WorkflowName,
    fw.WorkflowTypeRecID,
    fw.DefVersion,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    q.qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)') AS QAID
INTO #Blocks
FROM #FilteredWorkflows fw
CROSS APPLY fw.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop)
WHERE (@BlockType = '' OR LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) = @BlockType);

-- =============================================
-- PATH 2: Task blocks (teamblock property)
-- =============================================

SELECT DISTINCT
    fw.WorkflowName,
    fw.WorkflowTypeRecID,
    fw.DefVersion,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    LTRIM(RTRIM(p.prop.value('(value)[1]',  'nvarchar(255)'))) AS TeamName
INTO #TaskBlocks
FROM #FilteredWorkflows fw
CROSS APPLY fw.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="teamblock"]/groups/group/param[name="team"]') p(prop)
WHERE (@BlockType = '' OR LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) = @BlockType)
  AND LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) <> ''
  AND LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) NOT LIKE '$(%'
  AND (@TeamName = '' OR LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)'))) LIKE '%' + @TeamName + '%');

-- =============================================
-- Final result: UNION both paths with request offering status
-- =============================================

SELECT DISTINCT
    b.WorkflowName,
    b.DefVersion,
    ISNULL(srt.Status, 'No Offering') AS RequestOfferingStatus,
    b.BlockTitle,
    b.BlockType,
    LEFT(
        SUBSTRING(qa.Definition, pos.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, pos.ValStart, 500)) - 1
    ) AS TeamName
FROM #Blocks b
JOIN frs_def_quick_actions qa ON qa.Id = TRY_CAST(b.QAID AS uniqueidentifier)
CROSS APPLY (
    SELECT CHARINDEX('"ExpressionText":"', qa.Definition,
        CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)) + 18
) pos(ValStart)
LEFT JOIN ServiceReqFulfillmentPlan fp
    ON fp.WorkflowId = CAST(b.WorkflowTypeRecID AS varchar(50))
LEFT JOIN FusionLink fl
    ON fl.TargetID = fp.RecId
    AND fl.RelationshipName = 'ServiceReqTemplateAssociatedServiceReqFulfillmentP'
LEFT JOIN ServiceReqTemplate srt
    ON srt.RecId = fl.SourceID
WHERE CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition) > 0
  AND LEFT(
        SUBSTRING(qa.Definition, pos.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, pos.ValStart, 500)) - 1
    ) <> ''
  AND LEFT(
        SUBSTRING(qa.Definition, pos.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, pos.ValStart, 500)) - 1
    ) NOT LIKE '$(%'
  AND (@TeamName = '' OR LEFT(
        SUBSTRING(qa.Definition, pos.ValStart, 500),
        CHARINDEX('"', SUBSTRING(qa.Definition, pos.ValStart, 500)) - 1
    ) LIKE '%' + @TeamName + '%')
  AND (@Status = '' OR ISNULL(srt.Status, 'No Offering') LIKE '%' + @Status + '%')

UNION ALL

SELECT DISTINCT
    tb.WorkflowName,
    tb.DefVersion,
    ISNULL(srt.Status, 'No Offering') AS RequestOfferingStatus,
    tb.BlockTitle,
    tb.BlockType,
    tb.TeamName
FROM #TaskBlocks tb
LEFT JOIN ServiceReqFulfillmentPlan fp
    ON fp.WorkflowId = CAST(tb.WorkflowTypeRecID AS varchar(50))
LEFT JOIN FusionLink fl
    ON fl.TargetID = fp.RecId
    AND fl.RelationshipName = 'ServiceReqTemplateAssociatedServiceReqFulfillmentP'
LEFT JOIN ServiceReqTemplate srt
    ON srt.RecId = fl.SourceID
WHERE (@Status = '' OR ISNULL(srt.Status, 'No Offering') LIKE '%' + @Status + '%')

ORDER BY WorkflowName, BlockType, BlockTitle;

-- Cleanup
DROP TABLE #FilteredWorkflows;
DROP TABLE #Blocks;
DROP TABLE #TaskBlocks;
