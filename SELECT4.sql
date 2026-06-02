SELECT
    wt.Name,
    LTRIM(RTRIM(block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
    CAST(block.query('.') AS nvarchar(max))                  AS BlockXml
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type wt ON wf.WorkflowTypeLink_RecID = wt.RecID
CROSS APPLY (
    SELECT CAST(
        REPLACE(
        REPLACE(CAST(wf.Details AS nvarchar(max)),
            '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
            ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
    AS XML)
) AS x(XmlData)
CROSS APPLY x.XmlData.nodes('/scenario/blocks/block') AS b(block)
WHERE wt.Name = 'Audit Data Request Request form'
  AND wf.IsActive = 1;

