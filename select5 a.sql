select a.* from frs_def_workflow_definition a, frs_def_workflow_type b where a.WorkflowTypeLink_RecID = b.RecID and b.Name = 'Audit Data Request'

select a.* from frs_def_workflow_definition a, frs_def_workflow_type b where a.WorkflowTypeLink_RecID = b.RecID and b.Name = 'Audit Data Request'

select * from frs_def_workflow_type b, frs_def_workflow_definition a where b.Name like '%Audit Data%' and b.RecID = a.WorkflowTypeLink_RecID 

SELECT
    wt.Name,
    wf.RecID,
    wf.DefVersion,
    wf.IsActive,
    wf.IsPublished
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type       wt ON wf.WorkflowTypeLink_RecID = wt.RecID
WHERE wt.Name LIKE '%Audit Data%'
ORDER BY wf.DefVersion DESC;
