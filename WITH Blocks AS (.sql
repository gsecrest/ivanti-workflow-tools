WITH Blocks AS (
    SELECT DISTINCT
        wt.Name AS WorkflowName,
        LTRIM(RTRIM(block.value('(title)[1]', 'nvarchar(255)'))) AS BlockTitle,
        LTRIM(RTRIM(block.value('(type)[1]',  'nvarchar(50)')))  AS BlockType,
        qaprop.value('(groups/group/param[name="QAID"]/value)[1]', 'nvarchar(100)') AS QAID
    FROM frs_def_workflow_definition wf
    JOIN frs_def_workflow_type wt
        ON wf.WorkflowTypeLink_RecID = wt.RecID
    CROSS APPLY (
        SELECT CAST(
            REPLACE(REPLACE(CAST(wf.Details AS nvarchar(max)),
                '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
                ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
        AS XML)
    ) x(XmlData)
    CROSS APPLY x.XmlData.nodes('/scenario/blocks/block') b(block)
    CROSS APPLY block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop)
    WHERE wt.Name like ‘%Account Payable%’ 
),
WithTeamPos AS (
    SELECT
        b.WorkflowName,
        b.BlockTitle,
        b.BlockType,
        CHARINDEX('"ExpressionText":"', qa.Definition,
            CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)) + 18 AS ValStart,
        qa.Definition AS fd
    FROM Blocks b
    JOIN frs_def_quick_actions qa ON qa.Id = b.QAID
    WHERE CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition) > 0
)
SELECT DISTINCT
    WorkflowName,
    BlockTitle,
    BlockType,
    LEFT(SUBSTRING(fd, ValStart, 500),
         CHARINDEX('"', SUBSTRING(fd, ValStart, 500)) - 1) AS TeamName
FROM WithTeamPos
WHERE LEFT(SUBSTRING(fd, ValStart, 500),
           CHARINDEX('"', SUBSTRING(fd, ValStart, 500)) - 1) <> ''
ORDER BY BlockTitle;