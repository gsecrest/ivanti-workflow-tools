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
    const csv = "﻿" + lines.join("\r\n");

    return new NextResponse(csv, {
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
