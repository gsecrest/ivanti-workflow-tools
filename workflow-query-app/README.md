# Workflow Query App

A Next.js app for finding which team owns a block in an Ivanti workflow. Queries the latest version of all `*form` workflows in SQL Server and returns matching blocks with their team assignments.

## What it does

Searches across workflow definitions and returns matching blocks with their team assignments. Results can be exported to CSV directly from the results table.

| Column | Description |
|---|---|
| Workflow Name | Name of the workflow |
| Version | Latest definition version |
| Offering Status | Associated request offering status (Published, Design, No Offering) |
| Block Title | Title of the matching block |
| Block Type | `task`, `advancedtask`, or `update` |
| Team Name | Team assigned to the block |

Filters are optional — leaving any field blank searches across all values. When results are returned, **Copy to Clipboard** and **Export CSV** buttons appear in the results header. The clipboard copy uses tab-separated values so it pastes directly into Excel with columns aligned.

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

## Windows Deployment (no terminal required)

To run the app in the background on Windows without keeping a terminal open, use the included `setup-windows.bat` script. It installs PM2, builds the app for production, and configures it to start automatically on Windows boot.

**Prerequisites:**
- [Node.js](https://nodejs.org) installed
- `.env.local` file created in the project root (see Setup above)

**Steps:**
1. Clone the repository to the Windows machine
2. Create `.env.local` with your database credentials
3. Right-click `setup-windows.bat` and select **Run as Administrator**

The app will be available at [http://localhost:3000](http://localhost:3000) and will start automatically after every reboot.

**Useful PM2 commands:**
```bash
pm2 status                         # check if the app is running
pm2 logs workflow-query-app        # view app logs
pm2 restart workflow-query-app     # restart the app
pm2 stop workflow-query-app        # stop the app
```

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
