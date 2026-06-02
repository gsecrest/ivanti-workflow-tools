-- Columns on ServiceReqTemplate
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ServiceReqTemplate'
ORDER BY COLUMN_NAME;

-- Distinct status values on ServiceReqTemplate
SELECT DISTINCT Status FROM ServiceReqTemplate ORDER BY Status;

-- Verify join chain: workflow type -> fulfillment plan -> FusionLink -> ServiceReqTemplate
-- Pick any known workflow name and trace the chain
SELECT TOP 5
    wt.Name AS WorkflowName,
    wt.RecID AS WorkflowTypeRecID,
    fp.RecId AS FulfillmentPlanRecId,
    fp.WorkflowId,
    fl.SourceID,
    fl.TargetID,
    fl.RelationshipName,
    srt.RecId AS ServiceReqTemplateRecId,
    srt.Name AS RequestOfferingName,
    srt.Status
FROM frs_def_workflow_type wt
JOIN ServiceReqFulfillmentPlan fp ON fp.WorkflowId = CAST(wt.RecID AS varchar(50))
JOIN FusionLink fl ON fl.TargetID = fp.RecId
    AND fl.RelationshipName = 'ServiceReqTemplateAssociatedServiceReqFulfillmentP'
JOIN ServiceReqTemplate srt ON srt.RecId = fl.SourceID
WHERE wt.Name LIKE '%form'
ORDER BY wt.Name;
