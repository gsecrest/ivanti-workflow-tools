SELECT a.*
FROM frs_def_workflow_definition a
JOIN frs_def_workflow_type b ON a.WorkflowTypeLink_RecID = b.RecID
WHERE b.Name LIKE '%Audit Data Request%'
   OR b.Name LIKE '%RO%'
ORDER BY a.RecID DESC
SELECT
    wt.Name                                                                         AS WorkflowName,
    wf.RecID                                                                        AS WorkflowRecId,
    TRIM(block.value('(title)[1]',  'nvarchar(255)'))                               AS BlockTitle,
    TRIM(block.value('(type)[1]',   'nvarchar(50)'))                                AS BlockType,
    TRIM(team.value('(groups/group/param[name="team"]/value)[1]', 'nvarchar(100)')) AS TeamRecId
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type       wt  ON wf.WorkflowTypeLink_RecID = wt.RecID
CROSS APPLY (SELECT CAST(wf.Details AS XML)) AS x(XmlData)
CROSS APPLY x.XmlData.nodes('/scenario/blocks/block')                               AS b(block)
CROSS APPLY block.nodes('blockProperties/property[name="teamblock"]')               AS t(team)
WHERE TRIM(team.value('(groups/group/param[name="team"]/value)[1]', 'nvarchar(100)')) <> ''
ORDER BY wt.Name, BlockTitle;
