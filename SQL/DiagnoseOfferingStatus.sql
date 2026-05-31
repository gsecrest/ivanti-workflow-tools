-- Diagnose why a specific request offering is not appearing in results
-- Change the workflow name below to the one you are investigating
DECLARE @WorkflowName NVARCHAR(255) = 'Ivanti Test Request Form';

-- Step 1: Does the workflow exist in frs_def_workflow_type?
SELECT
    wt.RecID AS WorkflowTypeRecID,
    wt.Name  AS WorkflowName
FROM frs_def_workflow_type wt
WHERE wt.Name LIKE '%' + @WorkflowName + '%';

-- Step 2: Is it being picked up by the most-recent-version filter?
SELECT
    wt.Name AS WorkflowName,
    wf.DefVersion,
    wf.IsPublished
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type wt ON wf.WorkflowTypeLink_RecID = wt.RecID
WHERE wt.Name LIKE '%' + @WorkflowName + '%'
  AND wt.Name LIKE '%form'
  AND wt.Name NOT LIKE '%backup%'
  AND CAST(wf.DefVersion AS INT) = (
      SELECT MAX(CAST(wf2.DefVersion AS INT))
      FROM frs_def_workflow_definition wf2
      WHERE wf2.WorkflowTypeLink_RecID = wf.WorkflowTypeLink_RecID
  );

-- Step 3: Does ServiceReqFulfillmentPlan link to this workflow?
SELECT
    wt.RecID AS WorkflowTypeRecID,
    wt.Name  AS WorkflowName,
    fp.RecId AS FulfillmentPlanRecId,
    fp.Name  AS FulfillmentPlanName,
    fp.WorkflowId
FROM frs_def_workflow_type wt
LEFT JOIN ServiceReqFulfillmentPlan fp ON fp.WorkflowId = CAST(wt.RecID AS varchar(50))
WHERE wt.Name LIKE '%' + @WorkflowName + '%';

-- Step 4: Does FusionLink connect FulfillmentPlan to ServiceReqTemplate?
SELECT
    wt.Name  AS WorkflowName,
    fp.RecId AS FulfillmentPlanRecId,
    fl.SourceID,
    fl.TargetID,
    fl.RelationshipName
FROM frs_def_workflow_type wt
JOIN ServiceReqFulfillmentPlan fp ON fp.WorkflowId = CAST(wt.RecID AS varchar(50))
LEFT JOIN FusionLink fl ON fl.TargetID = fp.RecId
WHERE wt.Name LIKE '%' + @WorkflowName + '%';

-- Step 5: Full chain -- what Status does ServiceReqTemplate show?
SELECT
    wt.Name    AS WorkflowName,
    fp.RecId   AS FulfillmentPlanRecId,
    fl.RelationshipName,
    srt.RecId  AS ServiceReqTemplateRecId,
    srt.Name   AS RequestOfferingName,
    srt.Status AS RequestOfferingStatus
FROM frs_def_workflow_type wt
LEFT JOIN ServiceReqFulfillmentPlan fp ON fp.WorkflowId = CAST(wt.RecID AS varchar(50))
LEFT JOIN FusionLink fl ON fl.TargetID = fp.RecId
LEFT JOIN ServiceReqTemplate srt ON srt.RecId = fl.SourceID
WHERE wt.Name LIKE '%' + @WorkflowName + '%';
