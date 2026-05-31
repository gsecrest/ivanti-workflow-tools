# Ivanti Workflow Tools

SQL scripts, documentation, and a web app for auditing and analyzing Ivanti ITSM (Neurons) workflow definitions — specifically for identifying which teams are assigned within workflow blocks.

## Repository Structure

```
SQL/                                          ← SQL scripts and documentation
  FindTeamByBlockTypeAndWorkflow_v5.sql       ← Primary query (latest, optimised)
  FindTeamByBlockTypeAndWorkflow_v5_Documentation.docx
  FindTeamByBlockTypeAndWorkflow_v4.sql
  FindTeamByBlockTypeAndWorkflow_v4_Documentation.docx
  FindWorkflowsByTeamAndBlockType.sql
  FindWorkflowsByTeamName.sql
  GetAllBlockTypes.sql
  GetTeamsByBlockType.sql
  Diagnose*.sql                               ← Diagnostic/troubleshooting scripts
  Explore*.sql                                ← Schema exploration scripts

workflow-query-app/                           ← Next.js web interface
```

---

## Primary Script: FindTeamByBlockTypeAndWorkflow_v5.sql

Identifies which teams are assigned within Ivanti workflow blocks. Supports filtering by workflow name, block type, team name, and request offering status.

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `@WorkflowName` | *(all)* | Partial-match filter on workflow name |
| `@BlockType` | *(all)* | `task`, `advancedtask`, or `update` |
| `@TeamName` | `Risk Management Support` | Partial-match filter on team name |
| `@Status` | `Published` | Request offering status (e.g. `Published`, `Design`) |

### Output Columns

| Column | Description |
|---|---|
| WorkflowName | Name of the workflow |
| DefVersion | Latest version number |
| RequestOfferingStatus | Associated offering status, or `No Offering` if unlinked |
| BlockTitle | Display title of the block |
| BlockType | `task`, `advancedtask`, or `update` |
| TeamName | Team assigned within the block |

### How It Works

1. Identifies the latest version of each `*form` workflow using `ROW_NUMBER()` partitioned by workflow ID
2. Shreds the workflow XML definition to extract all blocks in a single pass
3. Resolves team assignments via two paths — QuickAction blocks (JSON string parsing) and task blocks (XML `teamblock` property)
4. Joins to `ServiceReqFulfillmentPlan` → `FusionLink` → `ServiceReqTemplate` to get the offering status
5. UNIONs both block paths and returns results sorted by workflow, block type, and block title

Full technical documentation is in `SQL/FindTeamByBlockTypeAndWorkflow_v5_Documentation.docx`. For a complete guide to all SQL scripts in this repo, see [SQL/README.md](SQL/README.md).

---

## Other SQL Scripts

| Script | Purpose |
|---|---|
| `FindWorkflowsByTeamAndBlockType.sql` | Find workflows containing blocks for a given team and block type |
| `FindWorkflowsByTeamName.sql` | Find all workflows referencing a specific team |
| `GetAllBlockTypes.sql` | List all distinct block types across all workflows |
| `GetAllBlockTypesByTeam.sql` | List block types grouped by team |
| `GetTeamsByBlockType.sql` | List teams grouped by block type |
| `DiagnoseOfferingStatus.sql` | Troubleshoot offering status join issues |
| `DiagnoseWorkflowBlocks.sql` | Inspect raw block data from a specific workflow |
| `DiagnoseWorkflowIdFormat.sql` | Verify workflow ID format for join compatibility |
| `ExploreServiceReqTemplate.sql` | Explore the service request template schema |
| `ExploreFulfillmentPlan.sql` | Explore the fulfillment plan schema |
| `ExploreFusionLink.sql` | Explore the FusionLink relationship table |

---

## Web App

`workflow-query-app/` is a Next.js browser interface over the v5 query. It provides the same four filters as the SQL parameters and displays results in a table with **Export CSV** and **Copy to Clipboard** options.

See [workflow-query-app/README.md](workflow-query-app/README.md) for setup instructions, or [workflow-query-app/BUILDING.md](workflow-query-app/BUILDING.md) for a full build guide.

The web app is also available as a standalone repository: [github.com/gsecrest/workflow-query-app](https://github.com/gsecrest/workflow-query-app)

---

## Requirements

- SQL Server 2016+ (uses XQuery, `TRY_CAST`, window functions)
- `SELECT` access on: `frs_def_workflow_definition`, `frs_def_workflow_type`, `frs_def_quick_actions`, `ServiceReqFulfillmentPlan`, `FusionLink`, `ServiceReqTemplate`, `StandardUserTeam`
- `tempdb` write access (scripts use temp tables and `CREATE INDEX`)
