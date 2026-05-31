-- Single result set to diagnose the full join chain for a specific workflow
DECLARE @WorkflowName NVARCHAR(255) = 'Ivanti Test Request Form';

SELECT
    wt.RecID                            AS WorkflowTypeRecID,
    wt.Name                             AS WorkflowName,
    fp.RecId                            AS FulfillmentPlanRecId,
    fp.WorkflowId                       AS FulfillmentPlan_WorkflowId,
    CAST(wt.RecID AS varchar(50))       AS WorkflowTypeRecID_AsVarchar,
    CASE WHEN fp.RecId IS NULL
         THEN 'BREAK: No FulfillmentPlan matched'
         ELSE 'OK' END                  AS FulfillmentPlanJoin,
    fl.RelationshipName                 AS FusionLink_RelationshipName,
    CASE WHEN fl.SourceID IS NULL
         THEN 'BREAK: No FusionLink matched'
         ELSE 'OK' END                  AS FusionLinkJoin,
    srt.RecId                           AS ServiceReqTemplateRecId,
    srt.Name                            AS RequestOfferingName,
    srt.Status                          AS RequestOfferingStatus,
    CASE WHEN srt.RecId IS NULL
         THEN 'BREAK: No ServiceReqTemplate matched'
         ELSE 'OK' END                  AS TemplateJoin
FROM frs_def_workflow_type wt
LEFT JOIN ServiceReqFulfillmentPlan fp
    ON fp.WorkflowId = CAST(wt.RecID AS varchar(50))
LEFT JOIN FusionLink fl
    ON fl.TargetID = fp.RecId
LEFT JOIN ServiceReqTemplate srt
    ON srt.RecId = fl.SourceID
WHERE wt.Name LIKE '%' + @WorkflowName + '%';
