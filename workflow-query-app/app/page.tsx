"use client";

import { useState, useEffect } from "react";

type Row = {
  WorkflowName: string;
  DefVersion: string;
  RequestOfferingStatus: string;
  BlockTitle: string;
  BlockType: string;
  TeamName: string;
};

const BLOCK_TYPES = ["", "task", "advancedtask", "update"];
const STATUSES = ["", "Published", "Design"];

export default function Home() {
  const [workflowName, setWorkflowName] = useState("");
  const [blockType, setBlockType] = useState("");
  const [teamName, setTeamName] = useState("Risk Management Support");
  const [status, setStatus] = useState("Published");
  const [teams, setTeams] = useState<string[]>([]);
  const [teamsLoading, setTeamsLoading] = useState(true);

  useEffect(() => {
    fetch("/api/teams")
      .then((r) => r.json())
      .then((data) => {
        if (data.teams) setTeams(data.teams);
      })
      .finally(() => setTeamsLoading(false));
  }, []);

  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [hasQueried, setHasQueried] = useState(false);

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
      if (data.error) {
        setError(data.error);
        setRows([]);
      } else {
        setRows(data.rows);
      }
    } catch {
      setError("Failed to reach the server.");
      setRows([]);
    } finally {
      setLoading(false);
    }
  }

  function clearAll() {
    setWorkflowName("");
    setBlockType("");
    setTeamName("");
    setStatus("");
    setRows([]);
    setHasQueried(false);
    setError("");
  }

  return (
    <main className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-6xl mx-auto">
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-gray-900">
            Find Team by Block Type &amp; Workflow
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Leave any field blank to search across all values.
          </p>
        </div>

        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-6 mb-6">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <div>
              <label className="block text-xs font-semibold text-gray-800 uppercase tracking-wide mb-1">
                Workflow Name
              </label>
              <input
                type="text"
                value={workflowName}
                onChange={(e) => setWorkflowName(e.target.value)}
                placeholder="All workflows"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-800 uppercase tracking-wide mb-1">
                Block Type
              </label>
              <select
                value={blockType}
                onChange={(e) => setBlockType(e.target.value)}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
              >
                {BLOCK_TYPES.map((bt) => (
                  <option key={bt} value={bt}>
                    {bt === "" ? "All block types" : bt}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-800 uppercase tracking-wide mb-1">
                Team Name
              </label>
              <select
                value={teamName}
                onChange={(e) => setTeamName(e.target.value)}
                disabled={teamsLoading}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white disabled:text-gray-400"
              >
                <option value="">All teams</option>
                {teams.map((t) => (
                  <option key={t} value={t}>{t}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-800 uppercase tracking-wide mb-1">
                Status
              </label>
              <select
                value={status}
                onChange={(e) => setStatus(e.target.value)}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
              >
                {STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {s === "" ? "All statuses" : s}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="flex gap-3 mt-5">
            <button
              onClick={runQuery}
              disabled={loading}
              className="bg-blue-600 hover:bg-blue-700 disabled:bg-blue-300 text-white font-semibold px-5 py-2 rounded-lg text-sm transition-colors"
            >
              {loading ? "Running…" : "Run Query"}
            </button>
            <button
              onClick={clearAll}
              className="bg-gray-100 hover:bg-gray-200 text-gray-700 font-semibold px-5 py-2 rounded-lg text-sm transition-colors"
            >
              Clear
            </button>
          </div>
        </div>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded-lg px-4 py-3 text-sm mb-4">
            <strong>Error:</strong> {error}
          </div>
        )}

        {hasQueried && !error && (
          <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
            <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between">
              <span className="text-sm font-semibold text-gray-700">Results</span>
              <span className="text-xs text-gray-400">
                {rows.length} row{rows.length !== 1 ? "s" : ""}
              </span>
            </div>

            {rows.length === 0 && !loading ? (
              <div className="px-5 py-10 text-center text-gray-400 text-sm">
                No results found for the selected filters.
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-gray-50 text-xs text-gray-500 uppercase tracking-wide">
                    <tr>
                      <th className="px-4 py-3 text-left font-semibold">Workflow Name</th>
                      <th className="px-4 py-3 text-left font-semibold">Version</th>
                      <th className="px-4 py-3 text-left font-semibold">Offering Status</th>
                      <th className="px-4 py-3 text-left font-semibold">Block Title</th>
                      <th className="px-4 py-3 text-left font-semibold">Block Type</th>
                      <th className="px-4 py-3 text-left font-semibold">Team Name</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {rows.map((row, i) => (
                      <tr key={i} className="hover:bg-gray-50 transition-colors">
                        <td className="px-4 py-3 text-gray-900">{row.WorkflowName}</td>
                        <td className="px-4 py-3 text-gray-600">{row.DefVersion}</td>
                        <td className="px-4 py-3">
                          <StatusBadge status={row.RequestOfferingStatus} />
                        </td>
                        <td className="px-4 py-3 text-gray-900">{row.BlockTitle}</td>
                        <td className="px-4 py-3">
                          <BlockTypeBadge type={row.BlockType} />
                        </td>
                        <td className="px-4 py-3 text-gray-900">{row.TeamName}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}
      </div>
    </main>
  );
}

function StatusBadge({ status }: { status: string }) {
  return <span className="text-sm text-gray-900">{status}</span>;
}

function BlockTypeBadge({ type }: { type: string }) {
  const color =
    type === "task"
      ? "bg-blue-100 text-blue-700"
      : type === "advancedtask"
      ? "bg-purple-100 text-purple-700"
      : type === "update"
      ? "bg-orange-100 text-orange-700"
      : "bg-gray-100 text-gray-500";
  return (
    <span className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${color}`}>
      {type}
    </span>
  );
}
