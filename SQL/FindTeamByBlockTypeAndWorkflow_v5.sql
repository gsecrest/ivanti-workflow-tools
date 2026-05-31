DECLARE @WorkflowName NVARCHAR(255) = '';                    -- leave blank to search all workflows
DECLARE @BlockType    NVARCHAR(50)  = '';                    -- task, advancedtask, update; leave blank for all
DECLARE @TeamName     NVARCHAR(255) = 'Risk Management Support'; -- leave blank to search all teams
DECLARE @Status       NVARCHAR(50)  = 'Published';           -- e.g. Published, Design; leave blank for all

IF OBJECT_ID('tempdb..#FilteredWorkflows') IS NOT NULL DROP TABLE #FilteredWorkflows;
IF OBJECT_ID('tempdb..#Blocks')            IS NOT NULL DROP TABLE #Blocks;
IF OBJECT_ID('tempdb..#TaskBlocks')        IS NOT NULL DROP TABLE #TaskBlocks;

-- =============================================================================
-- Step 1: Latest version per workflow type
-- ROW_NUMBER() replaces the correlated MAX subquery, which re-executed once per
-- row in the outer query. Window function scans frs_def_workflow_definition once.
-- =============================================================================
;WITH LatestVersions AS (
    SELECT
        RecID,
        WorkflowTypeLink_RecID,
        DefVersion,
        Details,
        ROW_NUMBER() OVER (
            PARTITION BY WorkflowTypeLink_RecID
            ORDER BY CAST(DefVersion AS INT) DESC
        ) AS rn
    FROM frs_def_workflow_definition
)
SELECT
    wt.Name                    AS WorkflowName,
    UPPER(lv.RecID)            AS WorkflowDefinitionRecID,   -- normalised once; avoids UPPER() in every join
    lv.DefVersion,
    CAST(
        REPLACE(REPLACE(CAST(lv.Details AS nvarchar(max)),
            '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
            ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
    AS XML) AS XmlData
INTO #FilteredWorkflows
FROM LatestVersions lv
JOIN frs_def_workflow_type wt ON lv.WorkflowTypeLink_RecID = wt.RecID
WHERE lv.rn = 1
  AND wt.Name LIKE '%form'
  AND wt.Name NOT LIKE '%backup%'
  AND (@WorkflowName = '' OR wt.Name LIKE '%' + @WorkflowName + '%');

-- Index used by the final LEFT JOIN on WorkflowDefinitionRecID
CREATE CLUSTERED INDEX IX_FW_RecID ON #FilteredWorkflows (WorkflowDefinitionRecID);

-- =============================================================================
-- PATH 1: QuickAction-based blocks (advancedtask, update)
-- =============================================================================
SELECT DISTINCT
    fw.WorkflowName,
    fw.WorkflowDefinitionRecID,
    fw.DefVersion,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    q.qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)') AS QAID
INTO #Blocks
FROM #FilteredWorkflows fw
CROSS APPLY fw.XmlData.nodes('/scenario/blocks/block') b(block)
CROSS APPLY b.block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop)
WHERE (@BlockType = '' OR LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) = @BlockType);

-- Index used by the JOIN to frs_def_quick_actions in the final query
CREATE CLUSTERED INDEX IX_Blocks_QAID ON #Blocks (QAID);

-- =============================================================================
-- PATH 2: Task blocks (teamblock property)
-- =============================================================================
SELECT DISTINCT
    fw.WorkflowName,
    fw.WorkflowDefinitionRecID,
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

-- Index used by the LEFT JOIN to WorkflowOffering in the final query
CREATE CLUSTERED INDEX IX_TaskBlocks_RecID ON #TaskBlocks (WorkflowDefinitionRecID);

-- =============================================================================
-- Final result
-- WorkflowOffering CTE replaces the identical 3-table LEFT JOIN that appeared
-- in both UNION branches; it now executes once and is referenced twice.
-- UPPER() is applied inside the CTE so the join condition stays sargable.
-- =============================================================================
;WITH WorkflowOffering AS (
    SELECT DISTINCT
        UPPER(fp.WorkflowId) AS WorkflowId,
        srt.Status
    FROM ServiceReqFulfillmentPlan fp
    JOIN FusionLink fl
        ON  fl.TargetID          = fp.RecId
        AND fl.RelationshipName  = 'ServiceReqTemplateAssociatedServiceReqFulfillmentP'
    JOIN ServiceReqTemplate srt ON srt.RecId = fl.SourceID
)
SELECT DISTINCT
    b.WorkflowName,
    b.DefVersion,
    ISNULL(wo.Status, 'No Offering') AS RequestOfferingStatus,
    b.BlockTitle,
    b.BlockType,
    tn.TeamName
FROM #Blocks b
JOIN frs_def_quick_actions qa ON qa.Id = TRY_CAST(b.QAID AS uniqueidentifier)
-- Compute TeamName once via CROSS APPLY(VALUES) instead of repeating the
-- CHARINDEX/SUBSTRING expression four times across SELECT and WHERE.
CROSS APPLY (VALUES (
    CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)
)) ownerPos (pos)
CROSS APPLY (VALUES (
    CHARINDEX('"ExpressionText":"', qa.Definition, ownerPos.pos) + 18
)) valStart (idx)
CROSS APPLY (VALUES (
    CASE WHEN ownerPos.pos > 0
         THEN LEFT(SUBSTRING(qa.Definition, valStart.idx, 500),
                   CHARINDEX('"', SUBSTRING(qa.Definition, valStart.idx, 500)) - 1)
    END
)) tn (TeamName)
LEFT JOIN WorkflowOffering wo ON wo.WorkflowId = b.WorkflowDefinitionRecID
WHERE tn.TeamName IS NOT NULL
  AND tn.TeamName <> ''
  AND tn.TeamName NOT LIKE '$(%'
  AND (@TeamName = '' OR tn.TeamName         LIKE '%' + @TeamName + '%')
  AND (@Status   = '' OR ISNULL(wo.Status, 'No Offering') LIKE '%' + @Status + '%')

UNION ALL

SELECT DISTINCT
    tb.WorkflowName,
    tb.DefVersion,
    ISNULL(wo.Status, 'No Offering') AS RequestOfferingStatus,
    tb.BlockTitle,
    tb.BlockType,
    tb.TeamName
FROM #TaskBlocks tb
LEFT JOIN WorkflowOffering wo ON wo.WorkflowId = tb.WorkflowDefinitionRecID
WHERE (@Status = '' OR ISNULL(wo.Status, 'No Offering') LIKE '%' + @Status + '%')

ORDER BY WorkflowName, BlockType, BlockTitle;

DROP TABLE #FilteredWorkflows;
DROP TABLE #Blocks;
DROP TABLE #TaskBlocks;
