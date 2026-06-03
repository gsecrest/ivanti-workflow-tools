import { NextResponse } from "next/server";
import { pool, poolConnect } from "@/lib/db";

export async function GET() {
  try {
    await poolConnect;

    const [teamsResult, groupsResult] = await Promise.all([
      pool.request().query(`
        SELECT DISTINCT Team
        FROM StandardUserTeam WITH (NOLOCK)
        WHERE ISNULL(WC_Inactive, 0) = 0
          AND IsServiceDesk = 1
          AND Team IS NOT NULL
          AND Team <> ''
        ORDER BY Team
      `),
      pool.request().query(`
        SELECT DISTINCT Name
        FROM ContactGroup WITH (NOLOCK)
        WHERE Status = 'Active'
          AND GroupType = 'Service Request Approval'
          AND Name IS NOT NULL
          AND Name <> ''
        ORDER BY Name
      `),
    ]);

    const teams         = teamsResult.recordset.map((r: { Team: string }) => r.Team);
    const approvalGroups = groupsResult.recordset.map((r: { Name: string }) => r.Name);

    return NextResponse.json({ teams, approvalGroups });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
