SELECT
    wt.Name                                                                         AS WorkflowName,
    TRIM(block.value('(title)[1]', 'nvarchar(255)'))                                AS BlockTitle,
    TRIM(block.value('(type)[1]',  'nvarchar(50)'))                                 AS BlockType,
    TRIM(team.value('(groups/group/param[name="team"]/value)[1]', 'nvarchar(255)')) AS TeamName
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type       wt  ON wf.WorkflowTypeLink_RecID = wt.RecID
CROSS APPLY (
    SELECT CAST(
        REPLACE(CAST(wf.Details AS nvarchar(max)), '<?xml version=''1.0'' encoding=''utf-16le'' ?>', '')
    AS XML)
)                                                                                    AS x(XmlData)
CROSS APPLY x.XmlData.nodes('/scenario/blocks/block')                               AS b(block)
CROSS APPLY block.nodes('blockProperties/property[name="teamblock"]')               AS t(team)
WHERE wt.Name like '%Audit Data%'
  AND TRIM(team.value('(groups/group/param[name="team"]/value)[1]', 'nvarchar(255)')) <> ''
ORDER BY BlockTitle;


SELECT TOP 10
    wt.Name                                          AS WorkflowName,
    block.value('(title)[1]', 'nvarchar(255)')       AS BlockTitle,
    block.value('(type)[1]',  'nvarchar(50)')        AS BlockType
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type wt ON wf.WorkflowTypeLink_RecID = wt.RecID
CROSS APPLY (
    SELECT CAST(
        REPLACE(CAST(wf.Details AS nvarchar(max)), '<?xml version=''1.0'' encoding=''utf-16le'' ?>', '')
    AS XML)
) AS x(XmlData)
CROSS APPLY x.XmlData.nodes('/scenario/blocks/block') AS b(block);

