#!/usr/bin/env node
/* eslint-disable no-console */

const fs = require("fs");

const mode = process.argv[2] || "build";

function b64(name) {
  const value = process.env[name] || "";
  return Buffer.from(value, "base64").toString("utf8");
}

function text(name, fallback = "") {
  return process.env[name] || fallback;
}

function cleanScalar(value) {
  let v = String(value || "").trim();
  v = v.replace(/^!!int\s+/, "");
  if (
    (v.startsWith("\"") && v.endsWith("\"")) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    try {
      return JSON.parse(v);
    } catch {
      return v.slice(1, -1);
    }
  }
  return v;
}

function parseActions(block) {
  const actions = [];
  let current = null;

  for (const rawLine of String(block || "").split(/\r?\n/)) {
    const line = rawLine.replace(/\r$/, "");
    if (!line.trim()) continue;

    const itemMatch = line.match(/^\s*-\s+([^:]+):\s*(.*)$/);
    if (itemMatch) {
      if (current) actions.push(current);
      current = {};
      current[itemMatch[1].trim()] = cleanScalar(itemMatch[2]);
      continue;
    }

    const fieldMatch = line.match(/^\s+([^:]+):\s*(.*)$/);
    if (fieldMatch && current) {
      current[fieldMatch[1].trim()] = cleanScalar(fieldMatch[2]);
    }
  }

  if (current) actions.push(current);

  return actions.map((action, index) => ({
    order: Number(action.order || index + 1),
    type: String(action.type || "session_log"),
    status: String(action.status || "completed"),
    description: String(action.description || action.summary || "Session log action"),
    filePath: String(action.filePath || "")
  }));
}

function buildIncoming() {
  const now = text("SESSION_LAST_UPDATED", new Date().toISOString());
  const actions = parseActions(b64("SESSION_ACTIONS_B64"));
  const turns = [];

  if (text("SESSION_HAS_TURN") === "1") {
    turns.push({
      requestId: text("SESSION_TURN_REQUEST_ID"),
      timestamp: text("SESSION_TURN_TIMESTAMP", now),
      queryText: b64("SESSION_QUERY_TEXT_B64") || text("SESSION_QUERY_TITLE"),
      queryTitle: text("SESSION_QUERY_TITLE"),
      response: b64("SESSION_RESPONSE_B64"),
      interpretation: "",
      status: text("SESSION_TURN_STATUS", "in_progress"),
      model: text("SESSION_MODEL", "unknown"),
      modelProvider: "",
      tokenCount: 0,
      tags: [],
      contextList: [],
      designDecisions: [],
      requirementsDiscovered: [],
      filesModified: actions.map(a => a.filePath).filter(Boolean),
      blockers: [],
      actions,
      processingDialog: []
    });
  }

  return {
    sourceType: text("SESSION_SOURCE_TYPE"),
    sessionId: text("SESSION_ID"),
    title: text("SESSION_TITLE"),
    model: text("SESSION_MODEL", "unknown"),
    started: text("SESSION_STARTED", now),
    lastUpdated: now,
    status: text("SESSION_STATUS", "in_progress"),
    turnCount: turns.length,
    totalTokens: 0,
    turns
  };
}

function readJson(path, fallback) {
  try {
    if (path && fs.existsSync(path)) {
      return JSON.parse(fs.readFileSync(path, "utf8"));
    }
  } catch {
    return fallback;
  }
  return fallback;
}

function mergeSessions(existing, incoming) {
  const sessions = Array.isArray(existing?.items) ? existing.items : [];
  const prior = sessions.find(item =>
    item &&
    String(item.sourceType || "") === String(incoming.sourceType || "") &&
    String(item.sessionId || "") === String(incoming.sessionId || ""));

  if (!prior) {
    return incoming;
  }

  const merged = {
    ...prior,
    ...incoming,
    turns: []
  };

  const byRequestId = new Map();
  for (const turn of Array.isArray(prior.turns) ? prior.turns : []) {
    if (turn?.requestId) byRequestId.set(String(turn.requestId), turn);
  }
  for (const turn of Array.isArray(incoming.turns) ? incoming.turns : []) {
    if (turn?.requestId) byRequestId.set(String(turn.requestId), turn);
  }

  merged.turns = Array.from(byRequestId.values());
  merged.turnCount = merged.turns.length;
  return merged;
}

if (mode === "build") {
  process.stdout.write(JSON.stringify(buildIncoming()));
  process.exit(0);
}

if (mode === "merge") {
  const existing = readJson(process.argv[3], { items: [] });
  const incoming = readJson(process.argv[4], null);
  if (!incoming) {
    console.error("incoming session JSON is required");
    process.exit(2);
  }
  process.stdout.write(JSON.stringify(mergeSessions(existing, incoming)));
  process.exit(0);
}

console.error(`unknown mode: ${mode}`);
process.exit(2);
