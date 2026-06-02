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
