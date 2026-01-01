// src/session-start-continuity.ts
import * as fs from "fs";
import * as path from "path";
import { execSync } from "child_process";
import * as http from "http";
var CLAUDE_MEM_PORT = process.env.CLAUDE_MEM_WORKER_PORT || "37777";
function getProjectName(cwd) {
  const home = process.env.HOME || "";
  if (cwd.startsWith(`${home}/flext`)) {
    return "flext";
  } else if (cwd.startsWith(`${home}/invest`)) {
    return "invest";
  } else if (cwd.includes("Continuous-Claude-v2")) {
    return "Continuous-Claude-v2";
  }
  return path.basename(cwd);
}
async function loadClaudeMemContext(project) {
  return new Promise((resolve) => {
    const url = `http://127.0.0.1:${CLAUDE_MEM_PORT}/api/context/inject?project=${encodeURIComponent(project)}`;
    const req = http.get(url, { timeout: 5e3 }, (res) => {
      let data = "";
      res.on("data", (chunk) => data += chunk);
      res.on("end", () => {
        if (data && data.startsWith("# [")) {
          resolve(data);
        } else {
          resolve("");
        }
      });
    });
    req.on("error", () => resolve(""));
    req.on("timeout", () => {
      req.destroy();
      resolve("");
    });
  });
}
async function isWorkerReady() {
  return new Promise((resolve) => {
    const url = `http://127.0.0.1:${CLAUDE_MEM_PORT}/api/readiness`;
    const req = http.get(url, { timeout: 2e3 }, (res) => {
      let data = "";
      res.on("data", (chunk) => data += chunk);
      res.on("end", () => {
        resolve(data.includes('"status":"ready"'));
      });
    });
    req.on("error", () => resolve(false));
    req.on("timeout", () => {
      req.destroy();
      resolve(false);
    });
  });
}
function pruneLedger(ledgerPath) {
  let content = fs.readFileSync(ledgerPath, "utf-8");
  const originalLength = content.length;
  content = content.replace(/\n### Session Ended \([^)]+\)\n- Reason: \w+\n/g, "");
  const agentReportsMatch = content.match(/## Agent Reports\n([\s\S]*?)(?=\n## |$)/);
  if (agentReportsMatch) {
    const agentReportsSection = agentReportsMatch[0];
    const reports = agentReportsSection.match(/### [^\n]+ \(\d{4}-\d{2}-\d{2}[^)]*\)[\s\S]*?(?=\n### |\n## |$)/g);
    if (reports && reports.length > 10) {
      const keptReports = reports.slice(-10);
      const newAgentReportsSection = "## Agent Reports\n" + keptReports.join("");
      content = content.replace(agentReportsSection, newAgentReportsSection);
    }
  }
  if (content.length !== originalLength) {
    fs.writeFileSync(ledgerPath, content);
    console.error(`Pruned ledger: ${originalLength} \u2192 ${content.length} bytes`);
  }
}
function getLatestHandoff(handoffDir) {
  if (!fs.existsSync(handoffDir)) return null;
  const handoffFiles = fs.readdirSync(handoffDir).filter((f) => (f.startsWith("task-") || f.startsWith("auto-handoff-")) && f.endsWith(".md")).sort((a, b) => {
    const statA = fs.statSync(path.join(handoffDir, a));
    const statB = fs.statSync(path.join(handoffDir, b));
    return statB.mtime.getTime() - statA.mtime.getTime();
  });
  if (handoffFiles.length === 0) return null;
  const latestFile = handoffFiles[0];
  const content = fs.readFileSync(path.join(handoffDir, latestFile), "utf-8");
  const isAutoHandoff = latestFile.startsWith("auto-handoff-");
  let taskNumber;
  let status;
  let summary;
  if (isAutoHandoff) {
    const typeMatch = content.match(/type:\s*auto-handoff/i);
    status = typeMatch ? "auto-handoff" : "unknown";
    const timestampMatch = latestFile.match(/auto-handoff-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})/);
    taskNumber = timestampMatch ? timestampMatch[1] : "auto";
    const inProgressMatch = content.match(/## In Progress\n([\s\S]*?)(?=\n## |$)/);
    summary = inProgressMatch ? inProgressMatch[1].trim().split("\n").slice(0, 3).join("; ").substring(0, 150) : "Auto-handoff from pre-compact";
  } else {
    const taskMatch = latestFile.match(/task-(\d+)/);
    taskNumber = taskMatch ? taskMatch[1] : "??";
    const statusMatch = content.match(/status:\s*(success|partial|blocked)/i);
    status = statusMatch ? statusMatch[1] : "unknown";
    const summaryMatch = content.match(/## What Was Done\n([\s\S]*?)(?=\n## |$)/);
    summary = summaryMatch ? summaryMatch[1].trim().split("\n").slice(0, 2).join("; ").substring(0, 150) : "No summary available";
  }
  return {
    filename: latestFile,
    taskNumber,
    status,
    summary,
    isAutoHandoff,
    fullPath: path.join(handoffDir, latestFile),
    isPending: status !== "success"
    // Pending if not completed
  };
}
function getGlobalHandoffs(projectDir) {
  const handoffsDir = path.join(projectDir, "thoughts", "shared", "handoffs");
  if (!fs.existsSync(handoffsDir)) return [];
  const handoffs = [];
  const files = fs.readdirSync(handoffsDir);
  for (const file of files) {
    const filePath = path.join(handoffsDir, file);
    const stat = fs.statSync(filePath);
    if (stat.isDirectory()) continue;
    if (file.match(/^\d{4}-\d{2}-\d{2}-.+\.md$/)) {
      const content = fs.readFileSync(filePath, "utf-8");
      const statusMatch = content.match(/status:\s*(pending|in-progress|complete|blocked)/i);
      const status = statusMatch ? statusMatch[1].toLowerCase() : "pending";
      const titleMatch = content.match(/^#\s+(.+)$/m);
      const summary = titleMatch ? titleMatch[1].substring(0, 150) : file.replace(/^\d{4}-\d{2}-\d{2}-/, "").replace(".md", "");
      handoffs.push({
        filename: file,
        taskNumber: file.replace(".md", ""),
        status,
        summary,
        isAutoHandoff: false,
        fullPath: filePath,
        isPending: status !== "complete" && status !== "success"
      });
    }
  }
  return handoffs.sort((a, b) => {
    const statA = fs.statSync(a.fullPath);
    const statB = fs.statSync(b.fullPath);
    return statB.mtime.getTime() - statA.mtime.getTime();
  });
}
function getUnmarkedHandoffs() {
  try {
    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const dbPath = path.join(projectDir, ".claude", "cache", "artifact-index", "context.db");
    if (!fs.existsSync(dbPath)) {
      return [];
    }
    const result = execSync(
      `sqlite3 "${dbPath}" "SELECT id, session_name, task_number, task_summary FROM handoffs WHERE outcome = 'UNKNOWN' ORDER BY indexed_at DESC LIMIT 5"`,
      { encoding: "utf-8", timeout: 3e3 }
    );
    if (!result.trim()) {
      return [];
    }
    return result.trim().split("\n").map((line) => {
      const [id, session_name, task_number, task_summary] = line.split("|");
      return { id, session_name, task_number: task_number || null, task_summary: task_summary || "" };
    });
  } catch (error) {
    return [];
  }
}
async function main() {
  const input = JSON.parse(await readStdin());
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const artifactDbPath = path.join(projectDir, ".claude", "cache", "artifact-index", "context.db");
  if (!fs.existsSync(artifactDbPath)) {
    const initScript = path.join(process.env.HOME || "", ".claude", "scripts", "init-project.sh");
    if (fs.existsSync(initScript)) {
      try {
        execSync(`bash "${initScript}" --quiet`, {
          cwd: projectDir,
          timeout: 1e4
        });
        console.error("\u2713 Project auto-initialized for Continuous Claude");
      } catch (e) {
        console.error("\u26A0 Could not auto-initialize project");
      }
    }
  }
  const sessionType = input.source || input.type || "startup";
  const projectName = getProjectName(projectDir);
  let claudeMemContext = "";
  if (await isWorkerReady()) {
    claudeMemContext = await loadClaudeMemContext(projectName);
    if (claudeMemContext) {
      console.error(`\u2713 Claude-mem context loaded for ${projectName}`);
    }
  }
  const ledgerDir = path.join(projectDir, "thoughts", "ledgers");
  let ledgerContent = "";
  let sessionName = "";
  let currentFocus = "Unknown";
  let goalSummary = "No goal found";
  let handoffDir = "";
  let latestHandoff = null;
  if (fs.existsSync(ledgerDir)) {
    const ledgerFiles = fs.readdirSync(ledgerDir).filter((f) => f.startsWith("CONTINUITY_CLAUDE-") && f.endsWith(".md")).sort((a, b) => {
      const statA = fs.statSync(path.join(ledgerDir, a));
      const statB = fs.statSync(path.join(ledgerDir, b));
      return statB.mtime.getTime() - statA.mtime.getTime();
    });
    if (ledgerFiles.length > 0) {
      const mostRecent = ledgerFiles[0];
      const ledgerPath = path.join(ledgerDir, mostRecent);
      pruneLedger(ledgerPath);
      ledgerContent = fs.readFileSync(ledgerPath, "utf-8");
      const goalMatch = ledgerContent.match(/## Goal\n([\s\S]*?)(?=\n## |$)/);
      const nowMatch = ledgerContent.match(/- Now: ([^\n]+)/);
      goalSummary = goalMatch ? goalMatch[1].trim().split("\n")[0].substring(0, 100) : "No goal found";
      currentFocus = nowMatch ? nowMatch[1].trim() : "Unknown";
      sessionName = mostRecent.replace("CONTINUITY_CLAUDE-", "").replace(".md", "");
      handoffDir = path.join(projectDir, "thoughts", "shared", "handoffs", sessionName);
      latestHandoff = getLatestHandoff(handoffDir);
      console.error(`\u2713 Ledger loaded: ${sessionName} \u2192 ${currentFocus}`);
    }
  }
  let message = "";
  let additionalContext = "";
  if (ledgerContent || claudeMemContext) {
    if (sessionName) {
      message = `[${sessionType}] Session: ${sessionName} | Focus: ${currentFocus}`;
      if (latestHandoff) {
        const handoffLabel = latestHandoff.isAutoHandoff ? `auto (${latestHandoff.status})` : `task-${latestHandoff.taskNumber} (${latestHandoff.status})`;
        message += ` | Handoff: ${handoffLabel}`;
      }
      if (claudeMemContext) {
        message += " | Claude-mem: \u2713";
      }
    } else if (claudeMemContext) {
      message = `[${sessionType}] Claude-mem context loaded for ${projectName}`;
    }
  }
  const contextParts = [];
  if (claudeMemContext) {
    contextParts.push(`## Claude-Mem Context

${claudeMemContext}`);
  }
  if (ledgerContent) {
    contextParts.push(`## Continuity Ledger

Loaded from: CONTINUITY_CLAUDE-${sessionName}.md

${ledgerContent}`);
  }
  if (latestHandoff && handoffDir) {
    const handoffPath = path.join(handoffDir, latestHandoff.filename);
    if (fs.existsSync(handoffPath)) {
      const handoffContent = fs.readFileSync(handoffPath, "utf-8");
      const handoffLabel = latestHandoff.isAutoHandoff ? "Auto-handoff" : "Task Handoff";
      const truncatedHandoff = handoffContent.length > 2e3 ? handoffContent.substring(0, 2e3) + "\n\n[... truncated, read full file if needed]" : handoffContent;
      contextParts.push(`## Latest ${handoffLabel}

File: ${latestHandoff.filename}
Status: ${latestHandoff.status}

${truncatedHandoff}`);
    }
  }
  if (sessionType !== "startup") {
    const unmarkedHandoffs = getUnmarkedHandoffs();
    if (unmarkedHandoffs.length > 0) {
      let unmarkedSection = `## Unmarked Session Outcomes

`;
      unmarkedSection += `Consider marking these to improve future recommendations:

`;
      for (const h of unmarkedHandoffs) {
        const taskLabel = h.task_number ? `task-${h.task_number}` : "handoff";
        const summaryPreview = h.task_summary ? h.task_summary.substring(0, 60) + "..." : "(no summary)";
        unmarkedSection += `- **${h.session_name}/${taskLabel}** (ID: \`${h.id.substring(0, 8)}\`): ${summaryPreview}
`;
      }
      contextParts.push(unmarkedSection);
    }
  }
  const globalHandoffs = getGlobalHandoffs(projectDir);
  const pendingHandoffs = globalHandoffs.filter((h) => h.isPending);
  if (pendingHandoffs.length > 0) {
    const mostRecentPending = pendingHandoffs[0];
    const handoffContent = fs.readFileSync(mostRecentPending.fullPath, "utf-8");
    const truncatedContent = handoffContent.length > 3e3 ? handoffContent.substring(0, 3e3) + "\n\n[... truncated]" : handoffContent;
    let handoffSection = `## \u{1F6A8} PENDING HANDOFFS DETECTED - AUTO-RESUME

`;
    handoffSection += `**${pendingHandoffs.length} pending handoff(s) found. Most recent:**

`;
    handoffSection += `**File:** \`${mostRecentPending.fullPath}\`
`;
    handoffSection += `**Summary:** ${mostRecentPending.summary}
`;
    handoffSection += `**Status:** ${mostRecentPending.status}

`;
    handoffSection += `### Handoff Content:

${truncatedContent}

`;
    if (pendingHandoffs.length > 1) {
      handoffSection += `### Other Pending Handoffs:
`;
      for (const h of pendingHandoffs.slice(1, 4)) {
        handoffSection += `- \`${h.filename}\`: ${h.summary}
`;
      }
      handoffSection += "\n";
    }
    handoffSection += `---

`;
    handoffSection += `**\u26A1 ACTION REQUIRED:** Resume work from the handoff above.
`;
    handoffSection += `Read the full handoff, understand the context, and continue the work.
`;
    handoffSection += `When complete, update the handoff status to \`complete\`.
`;
    contextParts.push(handoffSection);
    if (message) {
      message = `\u{1F6A8} PENDING HANDOFF | ${message}`;
    } else {
      message = `\u{1F6A8} PENDING HANDOFF: ${mostRecentPending.filename}`;
    }
    console.error(`\u{1F6A8} Auto-resuming handoff: ${mostRecentPending.filename}`);
  }
  if (contextParts.length > 0) {
    additionalContext = contextParts.join("\n\n---\n\n");
  }
  if (!message && !additionalContext) {
    if (sessionType !== "startup") {
      console.error(`\u26A0 No ledger or claude-mem context found.`);
      message = `[${sessionType}] No context found. Run /continuity_ledger to track session state.`;
    }
  }
  const output = { result: "continue" };
  if (message) {
    output.message = message;
    output.systemMessage = message;
  }
  if (additionalContext) {
    output.hookSpecificOutput = {
      hookEventName: "SessionStart",
      additionalContext
    };
  }
  console.log(JSON.stringify(output));
}
async function readStdin() {
  return new Promise((resolve) => {
    let data = "";
    process.stdin.on("data", (chunk) => data += chunk);
    process.stdin.on("end", () => resolve(data));
  });
}
main().catch(console.error);
