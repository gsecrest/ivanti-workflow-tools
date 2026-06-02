SELECT
wt.Name AS WorkflowName,
LTRIM(RTRIM(block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
LTRIM(RTRIM(block.value('(type)[1]', 'nvarchar(50)'))) AS BlockType,
LTRIM(RTRIM(team.value('(groups/group/param[name="team"]/value)[1]',
'nvarchar(255)'))) AS TeamName
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
CROSS APPLY block.nodes('blockProperties/property[name="teamblock"]') AS t(team)
WHERE wt.Name = 'Audit Data Request Request form'
AND LTRIM(RTRIM(team.value('(groups/group/param[name="team"]/value)[1]',
'nvarchar(255)'))) <> ''
ORDER BY BlockTitle;