-- Explore FusionLink structure
SELECT TOP 10 * FROM FusionLink;

-- Find relationship names linking ServiceReqTemplate to anything
SELECT DISTINCT RelationshipName
FROM FusionLink
WHERE RelationshipName LIKE '%ServiceReq%'
ORDER BY RelationshipName;

-- Explore columns on ServiceReqFulfillmentPlan to find workflow link column
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ServiceReqFulfillmentPlan'
ORDER BY COLUMN_NAME;

-- Preview ServiceReqFulfillmentPlan data
SELECT TOP 10 * FROM ServiceReqFulfillmentPlan;
