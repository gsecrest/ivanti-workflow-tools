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
