# SQL Scripts — Ivanti Workflow Analysis

SQL scripts for auditing Ivanti ITSM (Neurons) workflow definitions. All scripts target the same SQL Server database and share a common set of tables.

---

## Primary Script

### FindTeamByBlockTypeAndWorkflow_v8.sql *(recommended)*

The main audit query. Returns workflow blocks and their assigned teams or approval groups, with filtering by workflow name, block type, team/group, and offering status.

**Parameters** — edit the four `DECLARE` statements at the top:

```sql
DECLARE @WorkflowName NVARCHAR(255) = '';   -- blank = all workflows
DECLARE @BlockType    NVARCHAR(50)  = '';   -- blank = all block types
DECLARE @TeamName     NVARCHAR(255) = '';   -- blank = all teams and groups
DECLARE @Status       NVARCHAR(50)  = '';   -- blank = all statuses
```

**Supported block types:**

| Block Type | Team source |
|---|---|
| `task` | `teamblock` property in workflow XML |
| `advancedtask`, `update`, `create`, `notification`, `quickaction`, `createnew0002` | `OwnerTeam` in `frs_def_quick_actions.Definition` via CHARINDEX |
| `vote0007`, `vote` | `contactgroup` GUID in workflow XML → joined to `ContactGroup.Name` |

**Output:**

| Column | Description |
|---|---|
| WorkflowName | Workflow name |
| DefVersion | Latest version number |
| RequestOfferingStatus | Offering status, or `No Offering` if unlinked |
| BlockTitle | Block display title |
| BlockType | `task`, `advancedtask`, or `update` |
| TeamName | Team assigned to the block |

Full technical documentation: [FindTeamByBlockTypeAndWorkflow_v8_Documentation.docx](FindTeamByBlockTypeAndWorkflow_v8_Documentation.docx)

---

## Version History

| File | Notes |
|---|---|
| `FindTeamByBlockTypeAndWorkflow.sql` | v1 — initial version |
| `FindTeamByBlockTypeAndWorkflow_v2.sql` | v2 |
| `FindTeamByBlockTypeAndWorkflow_v3.sql` | v3 |
| `FindTeamByBlockTypeAndWorkflow_v4.sql` | v4 — see v4 documentation |
| `FindTeamByBlockTypeAndWorkflow_v5.sql` | v5 — performance-optimised rewrite; same output as v4 |
| `FindTeamByBlockTypeAndWorkflow_v6.sql` | v6 — single XML shred pass (#AllBlocks); WorkflowOffering materialised as temp table |
| `FindTeamByBlockTypeAndWorkflow_v7.sql` | v7 — NOLOCK hints, DISTINCT fix on #AllBlocks, improved CHARINDEX null guard |
| `FindTeamByBlockTypeAndWorkflow_v8.sql` | v8 — PATH 3 for vote0007/vote approval blocks via ContactGroup; expand QuickAction path to cover create, notification, quickaction, createnew0002 *(current)* |

Documentation is available for v4, v5, v7, and v8:
- [FindTeamByBlockTypeAndWorkflow_v4_Documentation.docx](FindTeamByBlockTypeAndWorkflow_v4_Documentation.docx)
- [FindTeamByBlockTypeAndWorkflow_v5_Documentation.docx](FindTeamByBlockTypeAndWorkflow_v5_Documentation.docx)
- [FindTeamByBlockTypeAndWorkflow_v7_Documentation.docx](FindTeamByBlockTypeAndWorkflow_v7_Documentation.docx)
- [FindTeamByBlockTypeAndWorkflow_v8_Documentation.docx](FindTeamByBlockTypeAndWorkflow_v8_Documentation.docx)

---

## Supporting Scripts

### Search & Discovery

| Script | Description |
|---|---|
| `FindWorkflowsByTeamAndBlockType.sql` | Find workflows containing blocks for a given team and block type |
| `FindWorkflowsByTeamAndBlockType_v2.sql` | Updated version |
| `FindWorkflowsByTeamName.sql` | Find all workflows referencing a specific team |
| `FindWorkflowsByTeamName_v2.sql` | Updated version |
| `FindTeamByRO.sql` | Find teams by request offering |
| `FindROByTeam2min.sql` | Find request offerings by team (optimised) |
| `FinalFindTeamInRO.sql` | Find team assignments in request offerings |

### Block Type Analysis

| Script | Description |
|---|---|
| `GetAllBlockTypes.sql` | List all distinct block types across all workflows |
| `GetAllBlockTypes_AllWorkflows.sql` | Block types across all workflows (broader scope) |
| `GetAllBlockTypesByTeam.sql` | Block types grouped by team |
| `GetTeamsByBlockType.sql` | Teams grouped by block type |
| `GetTeamsByBlockType_NoExpressions.sql` | Same, excluding dynamic expression values |

### Diagnostics & Troubleshooting

| Script | Description |
|---|---|
| `DiagnoseOfferingStatus.sql` | Troubleshoot offering status join results |
| `DiagnoseOfferingStatus_Single.sql` | Single-workflow offering status diagnosis |
| `DiagnoseWorkflowBlocks.sql` | Inspect raw block data from a specific workflow |
| `DiagnoseWorkflowIdFormat.sql` | Verify workflow ID format for join compatibility |
| `InspectTaskBlockProperties.sql` | Inspect task block XML properties |

### Schema Exploration

| Script | Description |
|---|---|
| `ExploreFulfillmentPlan.sql` | Explore the `ServiceReqFulfillmentPlan` schema |
| `ExploreFusionLink.sql` | Explore the `FusionLink` relationship table |
| `ExploreServiceReqTemplate.sql` | Explore the `ServiceReqTemplate` schema |

---

## Documentation Generators

| Script | Description |
|---|---|
| `generate_doc.py` | Python script that generated the v4 Word documentation |
| `generate_doc_v5.py` | Python script that generated the v5 Word documentation |
| `generate_doc_v7.py` | Python script that generated the v7 Word documentation |
| `generate_doc_v8.py` | Python script that generated the v8 Word documentation |

---

## Database Tables Referenced

| Table | Purpose |
|---|---|
| `frs_def_workflow_definition` | Versioned workflow XML definitions |
| `frs_def_workflow_type` | Workflow names and types |
| `frs_def_quick_actions` | Quick Action JSON definitions (contains team assignments) |
| `ServiceReqFulfillmentPlan` | Links workflows to fulfillment plans |
| `FusionLink` | Relationship table linking fulfillment plans to request templates |
| `ServiceReqTemplate` | Request offering metadata including status |
| `StandardUserTeam` | Active service desk teams |
| `ContactGroup` | Contact groups including approval groups (`GroupType = 'Service Request Approval'`) |

---

## Requirements

- SQL Server 2016+ (XQuery, `TRY_CAST`, window functions)
- `SELECT` access on all tables listed above
- `tempdb` write access — scripts use temp tables (`#TempName`) and `CREATE INDEX`
