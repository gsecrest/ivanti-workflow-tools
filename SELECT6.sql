SELECT
    wfd.WorkflowDefinitionID,
    wfd.Name,
    j.[key],
    j.value,
    j.type
FROM Frs_def_workflow_definition wfd
CROSS APPLY OPENJSON(wfd.Definition) j
WHERE 
    j.value LIKE '%Team%'
    OR j.value LIKE '%Approval%'
    OR j.value LIKE '%Group%'
    