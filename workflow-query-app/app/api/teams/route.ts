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
