-- Columns on ServiceReqFulfillmentPlan (to find workflow link column)
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ServiceReqFulfillmentPlan'
ORDER BY COLUMN_NAME;

-- Columns on ServiceReqTemplate (to find published status column)
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ServiceReqTemplate'
ORDER BY COLUMN_NAME;

-- Preview ServiceReqFulfillmentPlan data
SELECT TOP 5 * FROM ServiceReqFulfillmentPlan;

-- Preview ServiceReqTemplate status values
SELECT DISTINCT Status FROM ServiceReqTemplate ORDER BY Status;
