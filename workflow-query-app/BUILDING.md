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

These variables are read at runtime by the API routes using `process.env`.

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
  description: "Find teams by workflow block type",
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

## Step 6: Build the teams API route

Create `app/api/teams/route.ts`. This endpoint returns all active service desk teams for the dropdown.

```ts
import { NextResponse } from "next/server";
import sql from "mssql";

const config: sql.config = {
  server: process.env.DB_SERVER!,
  database: process.env.DB_DATABASE!,
  user: process.env.DB_USER!,
  password: process.env.DB_PASSWORD!,
  port: parseInt(process.env.DB_PORT || "1433"),
  options: {
    encrypt: true,
    trustServerCertificate: true,
  },
};

export async function GET() {
  try {
    const pool = await sql.connect(config);
    const result = await pool.request().query(`
      SELECT DISTINCT Team
      FROM StandardUserTeam
      WHERE ISNULL(WC_Inactive, 0) = 0
        AND IsServiceDesk = 1
        AND Team IS NOT NULL
        AND Team <> ''
      ORDER BY Team
    `);
    await pool.close();
    const teams = result.recordset.map((r: { Team: string }) => r.Team);
    return NextResponse.json({ teams });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
```

**Key points:**
- The `config` object reads credentials from environment variables. The `!` asserts the value is non-null — make sure `.env.local` is populated before running.
- `trustServerCertificate: true` is needed for self-signed certs common in internal SQL Server instances.
- Always call `pool.close()` after the query to release the connection.

---

## Step 7: Build the query API route

Create `app/api/query/route.ts`. This is the main search endpoint — it accepts filter parameters and runs a multi-step SQL query that shreds workflow XML to extract block and team data.

```ts
import { NextRequest, NextResponse } from "next/server";
import sql from "mssql";

const config: sql.config = { /* same as above */ };

export async function POST(req: NextRequest) {
  const { workflowName, blockType, teamName, status } = await req.json();

  // See the full query in the source file — it:
  // 1. Finds the latest version of each *form workflow
  // 2. Shreds the XML definition into individual blocks
  // 3. Extracts team assignments via two paths (QuickAction and teamblock)
  // 4. Joins to ServiceReqFulfillmentPlan to get the offering status
  // 5. UNIONs both paths and returns sorted results

  try {
    const pool = await sql.connect(config);
    const result = await pool
      .request()
      .input("wf", sql.NVarChar(255), workflowName ?? "")
      .input("bt", sql.NVarChar(50),  blockType   ?? "")
      .input("tn", sql.NVarChar(255), teamName    ?? "")
      .input("st", sql.NVarChar(50),  status      ?? "")
      .query(query);
    await pool.close();
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

The final `SELECT` UNIONs `#Blocks` (looking up team from `frs_def_quick_actions`) with `#TaskBlocks`, joined to `#WorkflowOffering` for the status column.

---

## Step 8: Build the UI page

Replace `app/page.tsx` with the filter form and results table. The component is a single `"use client"` page with four state-driven filters.

### State

```tsx
const [workflowName, setWorkflowName] = useState("");
const [blockType, setBlockType]       = useState("");
const [teamName, setTeamName]         = useState("Risk Management Support");
const [status, setStatus]             = useState("Published");
const [teams, setTeams]               = useState<string[]>([]);
const [rows, setRows]                 = useState<Row[]>([]);
const [loading, setLoading]           = useState(false);
const [hasQueried, setHasQueried]     = useState(false);
const [error, setError]               = useState("");
```

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

### Results table

The results section only renders when `hasQueried && !error`. The "No results found" message checks `!loading` to avoid flashing during the fetch:

```tsx
{hasQueried && !error && (
  <div>
    {rows.length === 0 && !loading ? (
      <p>No results found for the selected filters.</p>
    ) : (
      <table>...</table>
    )}
  </div>
)}
```

### Block type badge helper

`BlockTypeBadge` maps known block types to colors; anything unrecognised gets a neutral grey:

```tsx
function BlockTypeBadge({ type }: { type: string }) {
  const color =
    type === "task"         ? "bg-blue-100 text-blue-700"   :
    type === "advancedtask" ? "bg-purple-100 text-purple-700" :
    type === "update"       ? "bg-orange-100 text-orange-700" :
                              "bg-gray-100 text-gray-500";
  return <span className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${color}`}>{type}</span>;
}
```

Offering Status renders as plain text (no badge) since the values vary and don't map cleanly to a fixed color set.

---

## Step 9: Run and verify

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). The Team Name dropdown should populate immediately. Click **Run Query** with default filters to confirm the database connection works.

**Common issues:**

| Symptom | Likely cause |
|---|---|
| Team dropdown stays empty | `.env.local` credentials wrong or DB unreachable |
| `encrypt` / SSL errors | Set `trustServerCertificate: true` in the mssql config |
| Empty results for valid filters | Workflow names in DB use a different casing or suffix — check the `LIKE '%form'` filter in the SQL |
| `No results found` flash on load | Missing `!loading` guard on the empty-state message |

---

## File structure summary

```
workflow-query-app/
├── .env.local                  ← DB credentials (not committed)
├── app/
│   ├── layout.tsx              ← Root layout, fonts
│   ├── globals.css             ← Tailwind v4 + CSS variables
│   ├── page.tsx                ← Filter UI + results table
│   └── api/
│       ├── teams/route.ts      ← GET active service desk teams
│       └── query/route.ts      ← POST workflow block search
├── package.json
└── tsconfig.json
```
