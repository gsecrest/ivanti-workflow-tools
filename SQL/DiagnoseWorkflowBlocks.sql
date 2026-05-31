DECLARE @WorkflowName NVARCHAR(255) = 'Purchase Software Not Found';

-- Show ALL blocks in the workflow, including those without a QuickAction
SELECT
    LTRIM(RTRIM(b.block.value('(title)[1]',  'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',   'nvarchar(50)')))  AS BlockType,
    LTRIM(RTRIM(b.block.value('(id)[1]',     'nvarchar(100)'))) AS BlockId,
    -- Show whether a QuickAction exists on this block
    CASE
        WHEN b.block.exist('blockProperties/property[name="QuickAction"]') = 1
        THEN 'Yes'
        ELSE 'No'
    END AS HasQuickAction,
    -- Show the QAID if one exists
    LTRIM(RTRIM(b.block.value(
        '(blockProperties/property[name="QuickAction"]/groups/group/param[name="QAID"]/value)[1]',
        'nvarchar(100)'
    ))) AS QAID
FROM frs_def_workflow_definition wf
JOIN frs_def_workflow_type wt
    ON wf.WorkflowTypeLink_RecID = wt.RecID
CROSS APPLY (
    SELECT CAST(
        REPLACE(REPLACE(CAST(wf.Details AS nvarchar(max)),
            '<?xml version=''1.0'' encoding=''utf-16le'' ?>', ''),
            ' xmlns=''http://frontrange.com/saas/workflow/Bpe_workflow.xsd''', '')
    AS XML) AS XmlData
) x
CROSS APPLY x.XmlData.nodes('/scenario/blocks/block') b(block)
WHERE wt.Name LIKE '%' + @WorkflowName + '%'
ORDER BY BlockType, BlockTitle;
