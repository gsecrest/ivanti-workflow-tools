# Building the Workflow Query App

This guide walks through building this app from scratch — a Next.js tool that lets you search Ivanti workflow definitions and see which team owns each block.

## Prerequisites

- [Node.js](https://nodejs.org) 18 or later
- Access to the Ivanti SQL Server database
- Basic familiarity with TypeScript and React

---

## Step 1: Create the Next.js app

```bash
npx create-next-app@latest workflow-query-app
```

When prompted, choose:
- TypeScript: **Yes**
- ESLint: **Yes**
- Tailwind CSS: **Yes**
- `src/` directory: **No**
- App Router: **Yes**
- Turbopack: **Yes**
- Import alias: **No** (or keep the default `@/*`)

```bash
cd workflow-query-app
```

---

## Step 2: Install the SQL Server driver

```bash
npm install mssql
npm install --save-dev @types/mssql
```

`mssql` is the Node.js driver for Microsoft SQL Server. It handles connection pooling and parameterized queries.

---

## Step 3: Configure environment variables

Create `.env.local` in the project root. This file is gitignored by default — never commit it.

```
DB_SERVER=your-sql-server-hostname
DB_DATABASE=your-database-name
DB_USER=your-username
DB_PASSWORD=your-password
DB_PORT=1433
```

For production deployments on Windows, use `DB_PASSWORD_ENCRYPTED` instead of `DB_PASSWORD` — see the DPAPI utility step below.

These variables are read at runtime by the API routes via `lib/db-password.ts`.

---

## Step 4: Update the root layout

Replace the contents of `app/layout.tsx` to set up fonts and a full-height body:

```tsx
import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Workflow Query App",
  description: "Find team block ownership in Ivanti workflows",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
```

---

## Step 5: Update global styles

Replace `app/globals.css` with Tailwind v4's import syntax plus CSS variables for light/dark mode:

```css
@import "tailwindcss";

:root {
  --background: #ffffff;
  --foreground: #171717;
}

@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --font-sans: var(--font-geist-sans);
  --font-mono: var(--font-geist-mono);
}

@media (prefers-color-scheme: dark) {
  :root {
    --background: #0a0a0a;
    --foreground: #ededed;
  }
}

body {
  background: var(--background);
  color: var(--foreground);
  font-family: Arial, Helvetica, sans-serif;
}
```

> **Note:** Tailwind v4 uses `@import "tailwindcss"` instead of the v3 `@tailwind base/components/utilities` directives.

---

## Step 6: Create the DPAPI password utility

Create `lib/db-password.ts`. This utility decrypts the database password at startup using Windows DPAPI when `DB_PASSWORD_ENCRYPTED` is set, and falls back to the plaintext `DB_PASSWORD` for local dev.

```ts
import { spawnSync } from "child_process";

function resolveDbPassword(): string {
  const encrypted = process.env.DB_PASSWORD_ENCRYPTED;
  if (encrypted) {
    const result = spawnSync(
      "powershell.exe",
      [
        "-NonInteractive",
        "-Command",
        "Add-Type -AssemblyName System.Security; [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect([System.Convert]::FromBase64String($env:ENCRYPTED_PW), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))",
      ],
      { env: { ...process.env, ENCRYPTED_PW: encrypted }, encoding: "utf8" }
    );
    if (result.status === 0) {
      return result.stdout.trim();
    }
  }
  return process.env.DB_PASSWORD ?? "";
}

export const dbPassword = resolveDbPassword();
```

**Key points:**
- `spawnSync` is used instead of `execSync` so the encrypted value is passed as an environment variable (`$env:ENCRYPTED_PW`) rather than interpolated into the command string — this avoids shell escaping issues with `+` and `/` characters in base64.
- `DataProtectionScope.CurrentUser` ties the encryption to the Windows user account that encrypted it. The same account must run the app.
- The function runs once at module load time; `dbPassword` is a stable export consumed by `lib/db.ts`.

---

## Step 7: Create the shared DB pool

Create `lib/db.ts`. All three API routes import from here so the app maintains a single persistent connection pool instead of opening and closing a connection on every request.

```ts
import sql from "mssql";
import { dbPassword } from "./db-password";

const config: sql.config = {
  server: process.env.DB_SERVER!,
  database: process.env.DB_DATABASE!,
  user: process.env.DB_USER!,
  password: dbPassword,
  port: parseInt(process.env.DB_PORT || "1433"),
  requestTimeout: 60000,
  connectionTimeout: 30000,
  options: {
    encrypt: true,
    trustServerCertificate: true,
  },
};

export const pool = new sql.ConnectionPool(config);
export const poolConnect = pool.connect();
```

**Key points:**
- `new sql.ConnectionPool(config)` creates the pool at module load time but does not connect yet.
- `pool.connect()` returns a promise that resolves when the initial connection is established. Each route handler `await`s `poolConnect` before running a query.
- Never call `pool.close()` in route handlers — doing so tears down the TCP connection and forces a reconnect on every request, which adds significant latency.
- `requestTimeout` is set to 60 seconds (default is 15s). The XML shredding query can take longer than 15s on large datasets — raising this prevents spurious timeout errors.
- `connectionTimeout` is set to 30 seconds (default is 15s) to allow more time to establish the initial TCP connection to SQL Server.

---

## Step 8: Create the shared SQL query

Create `lib/workflow-query.ts`. The workflow block query is identical for both the search and export routes — extracting it here eliminates duplication and makes it the single place to tune the SQL.

```ts
export const workflowQuery = `
DECLARE @WorkflowName NVARCHAR(255) = @wf;
-- ... (full query — see source file)
`;
```

**Key points:**
- `WITH (NOLOCK)` is added to all base-table reads (`frs_def_workflow_definition`, `frs_def_workflow_type`, `ServiceReqFulfillmentPlan`, `FusionLink`, `ServiceReqTemplate`, `frs_def_quick_actions`). This is a read-only reporting query; NOLOCK prevents it from blocking or being blocked by concurrent writes on the live Ivanti system.
- Temp table reads do not need NOLOCK — they are session-scoped.
- The `OwnerTeam` extraction in the final SELECT uses `CHARINDEX` string scanning rather than `OPENJSON`. Ivanti stores JavaScript Date literals (`new Date(...)`) in the `Definition` column, which is valid JavaScript but not valid JSON — `OPENJSON` validates the entire document and rejects it before reaching `$.FieldValues`. `CHARINDEX` tolerates the non-standard format because it never parses the document as JSON. The extraction finds `"FieldName":"OwnerTeam"` then searches forward for `"ExpressionText":"` from that position; if `ExpressionText` is null in the JSON (`"ExpressionText":null`), the second search returns 0 and `TeamName` is correctly set to NULL rather than grabbing arbitrary text.

---

## Step 9: Build the teams API route

Create `app/api/teams/route.ts`. This endpoint returns all active service desk teams for the dropdown.

```ts
import { NextResponse } from "next/server";
import { pool, poolConnect } from "@/lib/db";

export async function GET() {
  try {
    await poolConnect;
    const result = await pool.request().query(`
      SELECT DISTINCT Team
      FROM StandardUserTeam WITH (NOLOCK)
      WHERE ISNULL(WC_Inactive, 0) = 0
        AND IsServiceDesk = 1
        AND Team IS NOT NULL
        AND Team <> ''
      ORDER BY Team
    `);
    const teams = result.recordset.map((r: { Team: string }) => r.Team);
    return NextResponse.json({ teams });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

**Key points:**
- `await poolConnect` ensures the shared pool is connected before the first query. After that it resolves instantly on subsequent requests.
- DB config and credentials are centralised in `lib/db.ts` — no config duplication across routes.
- `trustServerCertificate: true` (set in `lib/db.ts`) is needed for self-signed certs common in internal SQL Server instances.

---

## Step 10: Build the query API route

Create `app/api/query/route.ts`. This is the main search endpoint — it accepts filter parameters and runs the multi-step SQL query from `lib/workflow-query.ts` that shreds workflow XML to extract block and team data.

```ts
import { NextRequest, NextResponse } from "next/server";
import sql from "mssql";
import { pool, poolConnect } from "@/lib/db";
import { workflowQuery } from "@/lib/workflow-query";

export async function POST(req: NextRequest) {
  const { workflowName, blockType, teamName, status } = await req.json();

  try {
    await poolConnect;
    const result = await pool
      .request()
      .input("wf", sql.NVarChar(255), workflowName ?? "")
      .input("bt", sql.NVarChar(50),  blockType   ?? "")
      .input("tn", sql.NVarChar(255), teamName    ?? "")
      .input("st", sql.NVarChar(50),  status      ?? "")
      .query(workflowQuery);
    return NextResponse.json({ rows: result.recordset });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

**Key points:**
- Always use `.input()` with typed parameters instead of string interpolation — this prevents SQL injection.
- The SQL uses temp tables (`#FilteredWorkflows`, `#AllBlocks`, etc.) to break the query into readable stages and avoid re-shredding XML multiple times.
- Passing an empty string `""` for any filter means "match all" — the SQL uses `@param = '' OR ...` for optional filtering.

### How the SQL query works

The query has five stages:

| Stage | What it does |
|---|---|
| `#FilteredWorkflows` | Gets the latest version of each `*form` workflow, parses the XML definition |
| `#AllBlocks` | Shreds all blocks from the XML in a single pass; applies block type filter |
| `#Blocks` | Extracts QuickAction-based blocks (`advancedtask`, `update`) via QAID |
| `#TaskBlocks` | Extracts task blocks via the `teamblock` property |
| `#WorkflowOffering` | Joins workflow IDs to their request offering status |

The final `SELECT` UNIONs two branches, both joined to `#WorkflowOffering` for the status column:

- **`#Blocks` branch** — joins to `frs_def_quick_actions` and uses `CHARINDEX` string scanning to extract the team name from the `Definition` column: it finds `"FieldName":"OwnerTeam"` then searches forward for `"ExpressionText":"` to read the value. `OPENJSON` cannot be used here because Ivanti stores JavaScript Date literals (`new Date(...)`) in the column, which are not valid JSON.
- **`#TaskBlocks` branch** — team name was already extracted from XML in the `#TaskBlocks` stage, so no further lookup is needed.

---

## Step 11: Build the CSV export route

Create `app/api/export/workflow-results.csv/route.ts`. This GET endpoint runs the same query as `/api/query` (imported from `lib/workflow-query.ts`) and returns the results as a CSV file. The filename is embedded in the URL path so browsers use it as the download name even when managed browser policies ignore `Content-Disposition` headers.

```ts
import { NextRequest, NextResponse } from "next/server";
import sql from "mssql";
import { pool, poolConnect } from "@/lib/db";
import { workflowQuery } from "@/lib/workflow-query";

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const workflowName = searchParams.get("workflowName") ?? "";
  const blockType    = searchParams.get("blockType")    ?? "";
  const teamName     = searchParams.get("teamName")     ?? "";
  const status       = searchParams.get("status")       ?? "";

  try {
    await poolConnect;
    const result = await pool
      .request()
      .input("wf", sql.NVarChar(255), workflowName)
      .input("bt", sql.NVarChar(50),  blockType)
      .input("tn", sql.NVarChar(255), teamName)
      .input("st", sql.NVarChar(50),  status)
      .query(workflowQuery);

    const escape = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const headers = ["Workflow Name", "Version", "Offering Status", "Block Title", "Block Type", "Team Name"];
    const lines = [
      headers.map(escape).join(","),
      ...result.recordset.map((r) =>
        [r.WorkflowName, r.DefVersion, r.RequestOfferingStatus, r.BlockTitle, r.BlockType, r.TeamName]
          .map(escape).join(",")
      ),
    ];

    return new NextResponse("﻿" + lines.join("\r\n"), {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition": 'attachment; filename="workflow-results.csv"',
      },
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

**Key points:**
- The route directory is literally named `workflow-results.csv` — this puts the filename in the URL path (`/api/export/workflow-results.csv`), which browsers use as the download filename even when organization policies override `Content-Disposition`.
- `﻿` is the UTF-8 BOM — required for Excel on Windows to recognize the encoding and open the file directly without an import wizard.
- Filters are passed as query string parameters since this is a GET request triggered by a plain `<a href>` link, not a form POST.

---

## Step 12: Build the UI page

Replace `app/page.tsx` with the filter form and results table. The component is a single `"use client"` page with four state-driven filters.

### State

```tsx
const [workflowName, setWorkflowName] = useState("");
const [blockType, setBlockType]       = useState("");
const [teamName, setTeamName]         = useState("");
const [status, setStatus]             = useState("");
const [teams, setTeams]               = useState<string[]>([]);
const [rows, setRows]                 = useState<Row[]>([]);
const [loading, setLoading]           = useState(false);
const [hasQueried, setHasQueried]     = useState(false);
const [error, setError]               = useState("");
const [copied, setCopied]             = useState(false);
```

- All filters default to `""` (empty string), which the API treats as "match all".
- `hasQueried` prevents showing the results panel before the first query runs.
- `teams` is populated on mount by calling `/api/teams`.

### Fetching teams on mount

```tsx
useEffect(() => {
  fetch("/api/teams")
    .then((r) => r.json())
    .then((data) => { if (data.teams) setTeams(data.teams); })
    .finally(() => setTeamsLoading(false));
}, []);
```

### Running a query

```tsx
async function runQuery() {
  setLoading(true);
  setError("");
  setHasQueried(true);
  try {
    const res = await fetch("/api/query", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ workflowName, blockType, teamName, status }),
    });
    const data = await res.json();
    if (data.error) { setError(data.error); setRows([]); }
    else { setRows(data.rows); }
  } catch {
    setError("Failed to reach the server.");
    setRows([]);
  } finally {
    setLoading(false);
  }
}
```

### Export CSV link

The **Export CSV** link is a plain `<a>` tag pointing to the server-side export route. No JavaScript is involved — clicking it triggers a normal browser navigation which the server responds to with a CSV download.

```tsx
const exportHref = `/api/export/workflow-results.csv?${new URLSearchParams({ workflowName, blockType, teamName, status }).toString()}`;

// In JSX:
<a href={exportHref} className="...">Export CSV</a>
```

**Key points:**
- Using a plain `<a>` tag (not a button with `onClick`) is more reliable in managed browser environments.
- `exportHref` is computed from React state, so it always reflects the current filter values when clicked.
- The server re-runs the query — the export is independent of the displayed results, so it always reflects the current filters even if the user changed them after running the query.

### Copy to Clipboard

The **Copy to Clipboard** button copies results as tab-separated values (TSV), which pastes into Excel with columns already aligned — no import wizard needed.

```tsx
const [copied, setCopied] = useState(false);

function copyToClipboard() {
  const headers = ["Workflow Name", "Version", "Offering Status", "Block Title", "Block Type", "Team Name"];
  const lines = [
    headers.join("\t"),
    ...rows.map((r) =>
      [r.WorkflowName, r.DefVersion, r.RequestOfferingStatus, r.BlockTitle, r.BlockType, r.TeamName].join("\t")
    ),
  ];
  navigator.clipboard.writeText(lines.join("\n")).then(() => {
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  });
}
```

The button label switches to **"Copied!"** for 2 seconds via the `copied` state, then resets.

**Key points:**
- TSV (tab-separated) rather than CSV is used because `navigator.clipboard.writeText` writes plain text. Tabs are the delimiter Excel recognises when pasting plain text into a sheet.
- `setTimeout` resets `copied` after 2 seconds so the button is ready to use again.

### Results table

The results section only renders when `hasQueried && !error`. The "No results found" message checks `!loading` to avoid flashing during the fetch.

---

## Step 13: Run and verify

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). The Team Name dropdown should populate immediately. Click **Run Query** with all filters blank to confirm the database connection works.

**Common issues:**

| Symptom | Likely cause |
|---|---|
| Team dropdown stays empty | `.env.local` credentials wrong or DB unreachable |
| `encrypt` / SSL errors | Set `trustServerCertificate: true` in the mssql config |
| Empty results for valid filters | Workflow names in DB use a different casing or suffix — check the `LIKE '%form'` filter in the SQL |
| `Login failed for user` with DPAPI | Key named `DB_PASSWORD` instead of `DB_PASSWORD_ENCRYPTED` in `.env.local` |
| Export CSV does nothing in Chrome | Add `http://localhost:3000` to Chrome's allowed pop-ups and redirects in site settings |

---

## File structure summary

```
workflow-query-app/
├── .env.local                       ← DB credentials (not committed)
├── lib/
│   ├── db.ts                        ← Shared connection pool and DB config
│   ├── db-password.ts               ← DPAPI password decryption utility
│   └── workflow-query.ts            ← Shared SQL query (query + export routes)
├── app/
│   ├── layout.tsx                   ← Root layout, fonts, page title
│   ├── globals.css                  ← Tailwind v4 + CSS variables
│   ├── page.tsx                     ← Filter UI + results table
│   └── api/
│       ├── teams/route.ts           ← GET active service desk teams
│       ├── query/route.ts           ← POST workflow block search
│       └── export/
│           └── workflow-results.csv/
│               └── route.ts         ← GET CSV export (filename in URL path)
├── ecosystem.config.js              ← PM2 process config
├── setup-windows.bat                ← Windows one-click setup script
├── package.json
└── tsconfig.json
```
