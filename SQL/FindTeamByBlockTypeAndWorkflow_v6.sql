DECLARE @WorkflowName NVARCHAR(255) = '';                    -- leave blank to search all workflows
DECLARE @BlockType    NVARCHAR(50)  = '';                    -- task, advancedtask, update; leave blank for all
DECLARE @TeamName     NVARCHAR(255) = 'Risk Management Support'; -- leave blank to search all teams
DECLARE @Status       NVARCHAR(50)  = 'Published';           -- e.g. Published, Design; leave blank for all

IF OBJECT_ID('tempdb..#FilteredWorkflows')  IS NOT NULL DROP TABLE #FilteredWorkflows;
IF OBJECT_ID('tempdb..#AllBlocks')          IS NOT NULL DROP TABLE #AllBlocks;
IF OBJECT_ID('tempdb..#Blocks')             IS NOT NULL DROP TABLE #Blocks;
IF OBJECT_ID('tempdb..#TaskBlocks')         IS NOT NULL DROP TABLE #TaskBlocks;
IF OBJECT_ID('tempdb..#WorkflowOffering')   IS NOT NULL DROP TABLE #WorkflowOffering;

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

CREATE CLUSTERED INDEX IX_FW_RecID ON #FilteredWorkflows (WorkflowDefinitionRecID);

-- =============================================================================
-- Step 2: Single XML shred pass over all blocks
-- v5 walked XmlData.nodes('/scenario/blocks/block') twice — once for PATH 1
-- (QuickAction) and once for PATH 2 (teamblock). A single pass here halves the
-- XML parsing cost; PATH-specific CROSS APPLYs below read the cheap stored XML
-- fragment rather than re-shredding the full document.
-- =============================================================================
SELECT DISTINCT
    fw.WorkflowName,
    fw.WorkflowDefinitionRecID,
    fw.DefVersion,
    LTRIM(RTRIM(b.block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
    b.block.query('.')                                          AS BlockXml
INTO #AllBlocks
FROM #FilteredWorkflows fw
CROSS APPLY fw.XmlData.nodes('/scenario/blocks/block') b(block)
WHERE (@BlockType = '' OR LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) = @BlockType);

CREATE CLUSTERED INDEX IX_AB_RecID ON #AllBlocks (WorkflowDefinitionRecID);

-- =============================================================================
-- PATH 1: QuickAction-based blocks (advancedtask, update)
-- QAID stored as uniqueidentifier so the JOIN to frs_def_quick_actions.Id is
-- type-matched and sargable — avoids the per-row TRY_CAST in the final query.
-- =============================================================================
SELECT DISTINCT
    ab.WorkflowName,
    ab.WorkflowDefinitionRecID,
    ab.DefVersion,
    ab.BlockTitle,
    ab.BlockType,
    TRY_CAST(
        q.qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)')
    AS uniqueidentifier) AS QAID
INTO #Blocks
FROM #AllBlocks ab
CROSS APPLY ab.BlockXml.nodes('block/blockProperties/property[name="QuickAction"]') q(qaprop);

CREATE CLUSTERED INDEX IX_Blocks_QAID ON #Blocks (QAID);

-- =============================================================================
-- PATH 2: Task blocks (teamblock property)
-- CROSS APPLY (VALUES) computes TeamName once; v5 evaluated the same
-- LTRIM(RTRIM(p.prop.value(...))) expression three times in WHERE.
-- =============================================================================
SELECT DISTINCT
    ab.WorkflowName,
    ab.WorkflowDefinitionRecID,
    ab.DefVersion,
    ab.BlockTitle,
    ab.BlockType,
    tv.TeamName
INTO #TaskBlocks
FROM #AllBlocks ab
CROSS APPLY ab.BlockXml.nodes('block/blockProperties/property[name="teamblock"]/groups/group/param[name="team"]') p(prop)
CROSS APPLY (VALUES (
    LTRIM(RTRIM(p.prop.value('(value)[1]', 'nvarchar(255)')))
)) tv (TeamName)
WHERE tv.TeamName <> ''
  AND tv.TeamName NOT LIKE '$(%'
  AND (@TeamName = '' OR tv.TeamName LIKE '%' + @TeamName + '%');

CREATE CLUSTERED INDEX IX_TaskBlocks_RecID ON #TaskBlocks (WorkflowDefinitionRecID);

-- =============================================================================
-- Step 3: Materialise WorkflowOffering as a temp table
-- v5 used a CTE referenced in both UNION branches; CTEs are not materialised,
-- so the 3-table join executed twice. One temp table + index executes it once.
-- =============================================================================
SELECT DISTINCT
    UPPER(fp.WorkflowId) AS WorkflowId,
    srt.Status
INTO #WorkflowOffering
FROM ServiceReqFulfillmentPlan fp
JOIN FusionLink fl
    ON  fl.TargetID         = fp.RecId
    AND fl.RelationshipName = 'ServiceReqTemplateAssociatedServiceReqFulfillmentP'
JOIN ServiceReqTemplate srt ON srt.RecId = fl.SourceID;

CREATE CLUSTERED INDEX IX_WO_WorkflowId ON #WorkflowOffering (WorkflowId);

-- =============================================================================
-- Final result
-- Outer DISTINCT removed from both UNION branches: #Blocks and #TaskBlocks are
-- already distinct, and the LEFT JOIN to #WorkflowOffering is many-to-one
-- (unique WorkflowId), so no fan-out can introduce duplicates.
-- =============================================================================
SELECT
    b.WorkflowName,
    b.DefVersion,
    ISNULL(wo.Status, 'No Offering') AS RequestOfferingStatus,
    b.BlockTitle,
    b.BlockType,
    tn.TeamName
FROM #Blocks b
JOIN frs_def_quick_actions qa ON qa.Id = b.QAID          -- type-matched; sargable
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
LEFT JOIN #WorkflowOffering wo ON wo.WorkflowId = b.WorkflowDefinitionRecID
WHERE tn.TeamName IS NOT NULL
  AND tn.TeamName <> ''
  AND tn.TeamName NOT LIKE '$(%'
  AND (@TeamName = '' OR tn.TeamName LIKE '%' + @TeamName + '%')
  AND (@Status   = '' OR ISNULL(wo.Status, 'No Offering') LIKE '%' + @Status + '%')

UNION ALL

SELECT
    tb.WorkflowName,
    tb.DefVersion,
    ISNULL(wo.Status, 'No Offering') AS RequestOfferingStatus,
    tb.BlockTitle,
    tb.BlockType,
    tb.TeamName
FROM #TaskBlocks tb
LEFT JOIN #WorkflowOffering wo ON wo.WorkflowId = tb.WorkflowDefinitionRecID
WHERE (@Status = '' OR ISNULL(wo.Status, 'No Offering') LIKE '%' + @Status + '%')

ORDER BY WorkflowName, BlockType, BlockTitle;

DROP TABLE #FilteredWorkflows;
DROP TABLE #AllBlocks;
DROP TABLE #Blocks;
DROP TABLE #TaskBlocks;
DROP TABLE #WorkflowOffering;
