CROSS APPLY block.nodes('blockProperties/property[name="QuickAction"]') q(qaprop)
    WHERE wt.Name like ‘%Account Payable%’
),
WithTeamPos AS (
WithPositions AS (
    SELECT
        b.WorkflowName,
        b.BlockTitle,
        b.BlockType,
        CHARINDEX('"ExpressionText":"', qa.Definition,
            CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)) + 18 AS ValStart,
        CASE WHEN CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition) > 0
             THEN CHARINDEX('"ExpressionText":"', qa.Definition,
                      CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition)) + 18
             ELSE 0 END AS TeamValStart,
        CASE WHEN CHARINDEX('"FieldName":"Service"', qa.Definition) > 0
             THEN CHARINDEX('"ExpressionText":"', qa.Definition,
                      CHARINDEX('"FieldName":"Service"', qa.Definition)) + 18
             ELSE 0 END AS ServiceValStart,
        qa.Definition AS fd
    FROM Blocks b
    JOIN frs_def_quick_actions qa ON qa.Id = b.QAID
    WHERE CHARINDEX('"FieldName":"OwnerTeam"', qa.Definition) > 0
       OR CHARINDEX('"FieldName":"Service"',   qa.Definition) > 0
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
    CASE WHEN TeamValStart > 0
         THEN LEFT(SUBSTRING(fd, TeamValStart, 500),
                   CHARINDEX('"', SUBSTRING(fd, TeamValStart, 500)) - 1)
         ELSE '' END AS TeamName,
    CASE WHEN ServiceValStart > 0
         THEN LEFT(SUBSTRING(fd, ServiceValStart, 500),
                   CHARINDEX('"', SUBSTRING(fd, ServiceValStart, 500)) - 1)
         ELSE '' END AS ServiceName
FROM WithPositions
WHERE (TeamValStart    > 0 AND LEFT(SUBSTRING(fd, TeamValStart,    500), CHARINDEX('"', SUBSTRING(fd, TeamValStart,    500)) -
1) <> '')
   OR (ServiceValStart > 0 AND LEFT(SUBSTRING(fd, ServiceValStart, 500), CHARINDEX('"', SUBSTRING(fd, ServiceValStart, 500)) -
1) <> '')
ORDER BY BlockTitle;