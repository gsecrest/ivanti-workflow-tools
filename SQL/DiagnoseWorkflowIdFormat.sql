-- Check if WorkflowId matches frs_def_workflow_definition.RecID (not the type table)
SELECT
    wt.Name                         AS WorkflowName,
    wt.RecID                        AS WorkflowTypeRecID,
    wfd.RecID                       AS WorkflowDefinitionRecID,
    wfd.DefVersion,
    fp.RecId                        AS FulfillmentPlanRecId,
    fp.WorkflowId                   AS FulfillmentPlan_WorkflowId,
    fl.RelationshipName             AS FusionLink_RelationshipName,
    srt.Name                        AS RequestOfferingName,
    srt.Status                      AS RequestOfferingStatus
FROM frs_def_workflow_type wt
JOIN frs_def_workflow_definition wfd
    ON wfd.WorkflowTypeLink_RecID = wt.RecID
LEFT JOIN ServiceReqFulfillmentPlan fp
    ON UPPER(fp.WorkflowId) = UPPER(wfd.RecID)
LEFT JOIN FusionLink fl
    ON fl.TargetID = fp.RecId
    AND fl.RelationshipName = 'ServiceReqTemplateAssociatedServiceReqFulfillmentP'
LEFT JOIN ServiceReqTemplate srt
    ON srt.RecId = fl.SourceID
WHERE wt.Name LIKE '%Ivanti Test Request Form%'
ORDER BY CAST(wfd.DefVersion AS INT) DESC;
