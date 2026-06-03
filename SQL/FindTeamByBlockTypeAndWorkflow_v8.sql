DECLARE @WorkflowName NVARCHAR(255) = '';   -- leave blank to search all workflows
DECLARE @BlockType    NVARCHAR(50)  = '';   -- task, advancedtask, update, create, notification, quickaction, createnew0002, vote0007, vote; leave blank for all
DECLARE @TeamName     NVARCHAR(255) = '';   -- leave blank to search all teams and approval groups
DECLARE @Status       NVARCHAR(50)  = '';   -- e.g. Published, Design; leave blank for all

IF OBJECT_ID('tempdb..#FilteredWorkflows') IS NOT NULL DROP TABLE #FilteredWorkflows;
IF OBJECT_ID('tempdb..#AllBlocks')         IS NOT NULL DROP TABLE #AllBlocks;
IF OBJECT_ID('tempdb..#Blocks')            IS NOT NULL DROP TABLE #Blocks;
IF OBJECT_ID('tempdb..#TaskBlocks')        IS NOT NULL DROP TABLE #TaskBlocks;
IF OBJECT_ID('tempdb..#ApprovalBlocks')    IS NOT NULL DROP TABLE #ApprovalBlocks;
IF OBJECT_ID('tempdb..#WorkflowOffering')  IS NOT NULL DROP TABLE #WorkflowOffering;

-- =============================================================================
-- Stage 1: Latest version per workflow type
-- ROW_NUMBER() replaces correlated MAX subquery; scans frs_def_workflow_definition once.
-- WITH (NOLOCK) on all base tables — read-only reporting query prevents
-- blocking or being blocked by concurrent writes on the live Ivanti system.
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
    FROM frs_def_workflow_definition WITH (NOLOCK)
)
SELECT
    wt.Name                    AS WorkflowName,
    UPPER(lv.RecID)            AS WorkflowDefinitionRecID,
    lv.DefVersion,
    CAST(
        REPLACE(REPLACE(CAST(lv.Details AS nvarchar(max)),
            '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
            ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
    AS XML) AS XmlData
INTO #FilteredWorkflows
FROM LatestVersions lv
JOIN frs_def_workflow_type wt WITH (NOLOCK) ON lv.WorkflowTypeLink_RecID = wt.RecID
WHERE lv.rn = 1
  AND wt.Name LIKE '%form'
  AND wt.Name NOT LIKE '%backup%'
  AND (@WorkflowName = '' OR wt.Name LIKE '%' + @WorkflowName + '%');

CREATE CLUSTERED INDEX IX_FW_RecID ON #FilteredWorkflows (WorkflowDefinitionRecID);

-- =============================================================================
-- Stage 2: Single XML shred pass over all blocks
-- No DISTINCT: XML type is not comparable in SQL Server; dedup happens at
-- the PATH steps below which do not carry the XML column forward.
-- =============================================================================
SELECT
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
-- PATH 1: QuickAction-based blocks
-- Covers: advancedtask, update, create, notification, quickaction, createnew0002
-- All carry a QuickAction property with a QAID GUID that resolves to an
-- OwnerTeam in frs_def_quick_actions.Definition via CHARINDEX (see final SELECT).
-- QAID stored as uniqueidentifier — type-matched JOIN to frs_def_quick_actions.Id
-- is sargable.
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
-- CROSS APPLY (VALUES) computes TeamName once instead of evaluating the same
-- XPath three times in WHERE.
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
-- PATH 3: Approval blocks (vote0007, vote)
-- Extracts the approver contact group GUID from the approvers property and
-- joins to ContactGroup to resolve it to a group name.
-- Only processes blocks where a contactgroup GUID is present (static group
-- assignment). Dynamic approvers (_unchecked, from field, from profile)
-- produce no GUID and are excluded by the JOIN.
-- =============================================================================
SELECT DISTINCT
    ab.WorkflowName,
    ab.WorkflowDefinitionRecID,
    ab.DefVersion,
    ab.BlockTitle,
    ab.BlockType,
    cg.Name AS TeamName
INTO #ApprovalBlocks
FROM #AllBlocks ab
CROSS APPLY ab.BlockXml.nodes('block/blockProperties/property[name="approvers"]/groups/group') g(grp)
CROSS APPLY (VALUES (
    UPPER(LTRIM(RTRIM(g.grp.value('(param[name="contactgroup"]/value)[1]', 'nvarchar(50)'))))
)) av (ContactGroupId)
JOIN ContactGroup cg WITH (NOLOCK) ON UPPER(cg.RecId) = av.ContactGroupId
WHERE ab.BlockType IN ('vote0007', 'vote')
  AND av.ContactGroupId <> ''
  AND (@TeamName = '' OR cg.Name LIKE '%' + @TeamName + '%');

CREATE CLUSTERED INDEX IX_ApprovalBlocks_RecID ON #ApprovalBlocks (WorkflowDefinitionRecID);

-- =============================================================================
-- Stage 3: Materialise WorkflowOffering as a temp table
-- A CTE referenced in all three UNION branches would re-execute the 3-table
-- join three times. One temp table + index executes it once.
-- =============================================================================
SELECT DISTINCT
    UPPER(fp.WorkflowId) AS WorkflowId,
    srt.Status
INTO #WorkflowOffering
FROM ServiceReqFulfillmentPlan fp WITH (NOLOCK)
JOIN FusionLink fl WITH (NOLOCK)
    ON  fl.TargetID         = fp.RecId
    AND fl.RelationshipName = 'ServiceReqTemplateAssociatedServiceReqFulfillmentP'
JOIN ServiceReqTemplate srt WITH (NOLOCK) ON srt.RecId = fl.SourceID;

CREATE CLUSTERED INDEX IX_WO_WorkflowId ON #WorkflowOffering (WorkflowId);

-- =============================================================================
-- Final result: UNION of all three paths
-- PATH 1 (QuickAction): team extracted from frs_def_quick_actions.Definition
--   via CHARINDEX. OPENJSON cannot be used — Ivanti stores JavaScript Date
--   literals (new Date(...)) in Definition, which are not valid JSON.
--   Two-step null guard: checks etPos.pos > 0 before extracting ExpressionText
--   to avoid returning arbitrary text when OwnerTeam has no value.
-- PATH 2 (task): team already in #TaskBlocks, no further lookup needed.
-- PATH 3 (approval): group name already resolved via ContactGroup JOIN.
-- =============================================================================
SELECT
    b.WorkflowName,
    b.DefVersion,
    ISNULL(wo.Status, 'No Offering') AS RequestOfferingStatus,
    b.BlockTitle,
    b.BlockType,
    tn.TeamName
FROM #Blocks b
JOIN frs_def_quick_actions qa WITH (NOLOCK) ON qa.Id = b.QAID
CROSS APPLY (VALUES (
    CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)
)) ownerPos (pos)
CROSS APPLY (VALUES (
    CASE WHEN ownerPos.pos > 0
         THEN CHARINDEX('"ExpressionText":"', qa.Definition, ownerPos.pos)
         ELSE 0
    END
)) etPos (pos)
CROSS APPLY (VALUES (
    CASE WHEN etPos.pos > 0
         THEN LEFT(SUBSTRING(qa.Definition, etPos.pos + 18, 500),
                   CHARINDEX('"', SUBSTRING(qa.Definition, etPos.pos + 18, 500)) - 1)
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

UNION ALL

SELECT
    ab.WorkflowName,
    ab.DefVersion,
    ISNULL(wo.Status, 'No Offering') AS RequestOfferingStatus,
    ab.BlockTitle,
    ab.BlockType,
    ab.TeamName
FROM #ApprovalBlocks ab
LEFT JOIN #WorkflowOffering wo ON wo.WorkflowId = ab.WorkflowDefinitionRecID
WHERE (@Status = '' OR ISNULL(wo.Status, 'No Offering') LIKE '%' + @Status + '%')

ORDER BY WorkflowName, BlockType, BlockTitle;

DROP TABLE #FilteredWorkflows;
DROP TABLE #AllBlocks;
DROP TABLE #Blocks;
DROP TABLE #TaskBlocks;
DROP TABLE #ApprovalBlocks;
DROP TABLE #WorkflowOffering;
