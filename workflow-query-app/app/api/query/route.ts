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
      .input("bt", sql.NVarChar(50), blockType ?? "")
      .input("tn", sql.NVarChar(255), teamName ?? "")
      .input("st", sql.NVarChar(50), status ?? "")
      .query(workflowQuery);

    return NextResponse.json({ rows: result.recordset });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
