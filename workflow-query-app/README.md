# Workflow Query App

A Next.js app for finding which team owns a block in an Ivanti workflow. Queries the latest version of all `*form` workflows in SQL Server and returns matching blocks with their team assignments.

## What it does

Searches across workflow definitions and returns rows showing:

| Column | Description |
|---|---|
| Workflow Name | Name of the workflow |
| Version | Latest definition version |
| Offering Status | Associated request offering status (Published, Design, No Offering) |
| Block Title | Title of the matching block |
| Block Type | `task`, `advancedtask`, or `update` |
| Team Name | Team assigned to the block |

Filters are optional — leaving any field blank searches across all values.

## Setup

Create a `.env.local` file in the project root:

```
DB_SERVER=your-sql-server
DB_DATABASE=your-database
DB_USER=your-username
DB_PASSWORD=your-password
DB_PORT=1433
```

Install dependencies and run the dev server:

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## API Routes

| Route | Method | Description |
|---|---|---|
| `/api/query` | POST | Run the workflow block query with filters |
| `/api/teams` | GET | Fetch active service desk teams for the Team Name dropdown |

### POST `/api/query`

**Body:**
```json
{
  "workflowName": "",
  "blockType": "task",
  "teamName": "Risk Management Support",
  "status": "Published"
}
```

**Response:**
```json
{
  "rows": [
    {
      "WorkflowName": "...",
      "DefVersion": "5",
      "RequestOfferingStatus": "Published",
      "BlockTitle": "...",
      "BlockType": "task",
      "TeamName": "Risk Management Support"
    }
  ]
}
```

## Project Structure

```
app/
  page.tsx          — UI with filters and results table
  layout.tsx        — Root layout
  globals.css       — Global styles
  api/
    query/route.ts  — Workflow block query endpoint
    teams/route.ts  — Active teams endpoint
```
