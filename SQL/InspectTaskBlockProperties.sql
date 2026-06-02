DECLARE @WorkflowName NVARCHAR(255) = 'Purchase Software Not Found';
DECLARE @BlockType    NVARCHAR(50)  = 'task';

-- Show all raw properties on task blocks to find where team is stored
SELECT DISTINCT
    LTRIM(RTRIM(b.block.value('(title)[1]',    'nvarchar(255)'))) AS BlockTitle,
    LTRIM(RTRIM(b.block.value('(type)[1]',     'nvarchar(50)')))  AS BlockType,
    LTRIM(RTRIM(p.prop.value('(name)[1]',      'nvarchar(255)'))) AS PropertyName,
    LTRIM(RTRIM(p.prop.value('(value)[1]',     'nvarchar(500)'))) AS PropertyValue
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
CROSS APPLY b.block.nodes('blockProperties/property') p(prop)
WHERE wt.Name LIKE '%' + @WorkflowName + '%'
  AND LTRIM(RTRIM(b.block.value('(type)[1]', 'nvarchar(50)'))) = @BlockType
ORDER BY BlockTitle, PropertyName;
