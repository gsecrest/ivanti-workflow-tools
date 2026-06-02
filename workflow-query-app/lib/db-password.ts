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
