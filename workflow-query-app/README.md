# Workflow Query App

A Next.js app for finding which team owns a block in an Ivanti workflow. Queries the latest version of all `*form` workflows in SQL Server and returns matching blocks with their team assignments.

## What it does

Searches across workflow definitions and returns matching blocks with their team assignments. Results can be exported to CSV directly from the results table.

| Column | Description |
|---|---|
| Workflow Name | Name of the workflow |
| Version | Latest definition version |
| Offering Status | Status of the associated request offering: `Published` or `Design`. Only workflows linked to a request offering are returned — unlinked workflows are excluded from results. |
| Block Title | Title of the matching block |
| Block Type | `task`, `advancedtask`, `update`, `create`, `notification`, `quickaction`, `createnew0002`, `vote0007`, or `vote` |
| Team / Group | Team assigned to the block, or approval group for `vote0007`/`vote` blocks (shown with a `group` tag) |

All filters default to "all values" — leave any field blank to search across everything. When results are returned, **Copy to Clipboard** and **Export CSV** buttons appear in the results header. The clipboard copy uses tab-separated values so it pastes directly into Excel with columns aligned.

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

## Encrypting the Database Password (Windows DPAPI)

For production deployments on Windows, the database password should be encrypted with Windows DPAPI so it is not stored in plaintext. The encrypted value is tied to your Windows user account — it cannot be decrypted on any other machine or user account.

**If you are using `setup-windows.bat`:** encryption is handled automatically. Just put `DB_PASSWORD=your-plaintext-password` in `.env.local` and run the script — it will encrypt the value, replace the line with `DB_PASSWORD_ENCRYPTED=<encrypted>`, and remove the plaintext before building the app.

**To encrypt manually** (e.g. to re-encrypt on a new machine, or if not using the `.bat`), run this in PowerShell on the Windows machine that will run the app:

```powershell
Add-Type -AssemblyName System.Security
[System.Convert]::ToBase64String(
  [System.Security.Cryptography.ProtectedData]::Protect(
    [System.Text.Encoding]::UTF8.GetBytes("your-plaintext-password"),
    $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
  )
)
```

Copy the output and update `.env.local`:

```
DB_SERVER=your-sql-server
DB_DATABASE=your-database
DB_USER=your-username
DB_PASSWORD_ENCRYPTED=<paste encrypted value here>
DB_PORT=1433
```

The app decrypts the password at startup via `lib/db-password.ts` using `spawnSync` and PowerShell DPAPI. If `DB_PASSWORD_ENCRYPTED` is not set, it falls back to `DB_PASSWORD` for local dev.

## Windows Deployment (no terminal required)

To run the app in the background on Windows without keeping a terminal open, use the included `setup-windows.bat` script. It installs PM2, builds the app for production, and configures it to start automatically on Windows boot.

**Prerequisites:**
- [Node.js](https://nodejs.org) installed
- `.env.local` file created in the project root with `DB_PASSWORD=your-plaintext-password` — **the script will not proceed without it, and will encrypt the password automatically before building**

**Steps:**
1. Clone the repository to the Windows machine
2. Create `.env.local` with your database credentials (use `DB_PASSWORD=` — the script encrypts it)
3. Right-click `setup-windows.bat` and select **Run as Administrator**

The app will be available at [http://localhost:3000](http://localhost:3000) and will start automatically after every reboot.

**Useful PM2 commands:**
```bash
pm2 status                              # check if the app is running
pm2 logs workflow-query-app             # view app logs
pm2 restart workflow-query-app          # restart the app
pm2 stop workflow-query-app             # stop the app
```

## Uninstalling

To fully remove the app and stop it from running on startup:

```bash
# 1. Stop and remove the PM2 process
pm2 delete workflow-query-app

# 2. Remove the Windows startup entry
npx pm2-windows-startup uninstall

# 3. Save the empty PM2 process list
pm2 save

# 4. (Optional) Uninstall PM2 and the startup manager globally
npm uninstall -g pm2 pm2-windows-startup
```

Then delete the app folder from your machine. The `.env.local` file (with your DB credentials) is inside that folder and will be removed along with it.

## Standalone SQL Script

A standalone version of the workflow query is kept at:

```
~/Downloads/Claude/SQL/FindTeamByBlockTypeAndWorkflow_v8.sql
```

This is the same logic as the app but written to run directly in SSMS. Parameters are declared at the top with hardcoded defaults — set them before running. Connection pool reuse is an app-layer concern and does not apply in SSMS; each execution is its own session.

Use it to test filter changes, inspect raw results, or verify query behaviour before updating `lib/workflow-query.ts`.

## API Routes

| Route | Method | Description |
|---|---|---|
| `/api/query` | POST | Run the workflow block query with filters |
| `/api/teams` | GET | Fetch service desk teams and approval groups for the Team / Group dropdown |
| `/api/export/workflow-results.csv` | GET | Download results as a CSV file |

### POST `/api/query`

**Body** (all fields optional — omit or pass empty string to match all):
```json
{
  "workflowName": "",
  "blockType": "",
  "teamName": "",
  "status": ""
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
      "BlockType": "task",   // or advancedtask, update, create, notification, quickaction, createnew0002, vote0007, vote
      "TeamName": "..."
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
    query/route.ts           — Workflow block query endpoint
    teams/route.ts           — Active teams endpoint
    export/
      workflow-results.csv/
        route.ts             — CSV export endpoint
lib/
  db.ts             — Shared connection pool and DB config
  db-password.ts    — DPAPI password decryption utility
  workflow-query.ts — Shared SQL query (used by query and export routes)
```

## Troubleshooting

### PM2 shows `errored` status

Run `pm2 logs workflow-query-app --lines 50` to see the crash output, then check the table below.

| Error | Cause | Fix |
|---|---|---|
| `SyntaxError: missing ) after argument list` in `node_modules/.bin/next` | PM2 tried to run the Unix bash wrapper instead of a Node.js file | Fixed in `ecosystem.config.js` — `script` now points to `node_modules/next/dist/bin/next` |
| DB connection errors or missing env vars | `.env.local` is missing or credentials are wrong | Create `.env.local` in the project root with the correct values (see Setup above) |
| `Login failed for user` | `DB_PASSWORD_ENCRYPTED` key name wrong in `.env.local` | Ensure the key is `DB_PASSWORD_ENCRYPTED`, not `DB_PASSWORD` |
| `Timeout: Request failed to complete in 15000ms` | Default mssql request timeout too short for large datasets | Already fixed in `lib/db.ts` — `requestTimeout` is set to 60s |

### PM2 config changes not taking effect

`pm2 restart` reuses the cached process definition and does **not** re-read `ecosystem.config.js`. After any change to `ecosystem.config.js`, run:

```bash
pm2 delete workflow-query-app
pm2 start ecosystem.config.js
pm2 save
```

### Export CSV does nothing in Chrome

If Chrome is managed by your organization (you'll see "Your browser is managed by your organization" in Chrome settings), it may block redirects from localhost. Fix:

1. In Chrome, go to **Settings → Privacy and security → Site settings → Pop-ups and redirects**
2. Under **Allowed to send pop-ups and use redirects**, click **Add**
3. Enter `http://localhost:3000` and click **Add**

Export CSV will work normally after this. Other browsers (Edge, Firefox) are not affected.

### App starts but team dropdown is empty or queries fail

Confirm the DB credentials in `.env.local` are correct and that the SQL Server is reachable from the machine running the app.
