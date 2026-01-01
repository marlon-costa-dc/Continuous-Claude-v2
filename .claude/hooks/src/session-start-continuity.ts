import * as fs from 'fs';
import * as path from 'path';
import { execSync } from 'child_process';
import * as http from 'http';

interface SessionStartInput {
  type?: 'startup' | 'resume' | 'clear' | 'compact';  // Legacy field
  source?: 'startup' | 'resume' | 'clear' | 'compact'; // Per docs
  session_id: string;
}

// Claude-Mem integration
const CLAUDE_MEM_PORT = process.env.CLAUDE_MEM_WORKER_PORT || '37777';

/**
 * Get project name from path for claude-mem queries
 */
function getProjectName(cwd: string): string {
  const home = process.env.HOME || '';

  if (cwd.startsWith(`${home}/flext`)) {
    return 'flext';
  } else if (cwd.startsWith(`${home}/invest`)) {
    return 'invest';
  } else if (cwd.includes('Continuous-Claude-v2')) {
    return 'Continuous-Claude-v2';
  }

  return path.basename(cwd);
}

/**
 * Load context from claude-mem worker via HTTP API
 */
async function loadClaudeMemContext(project: string): Promise<string> {
  return new Promise((resolve) => {
    const url = `http://127.0.0.1:${CLAUDE_MEM_PORT}/api/context/inject?project=${encodeURIComponent(project)}`;

    const req = http.get(url, { timeout: 5000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        // Check if we got valid context (should start with "# [project]")
        if (data && data.startsWith('# [')) {
          resolve(data);
        } else {
          resolve('');
        }
      });
    });

    req.on('error', () => resolve(''));
    req.on('timeout', () => {
      req.destroy();
      resolve('');
    });
  });
}

/**
 * Check if claude-mem worker is ready
 */
async function isWorkerReady(): Promise<boolean> {
  return new Promise((resolve) => {
    const url = `http://127.0.0.1:${CLAUDE_MEM_PORT}/api/readiness`;

    const req = http.get(url, { timeout: 2000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve(data.includes('"status":"ready"'));
      });
    });

    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
  });
}

interface HandoffSummary {
  filename: string;
  taskNumber: string;
  status: string;
  summary: string;
  isAutoHandoff: boolean;
}

/**
 * Prune ledger to prevent bloat:
 * 1. Remove all "Session Ended" entries
 * 2. Keep only the last 10 agent reports
 */
function pruneLedger(ledgerPath: string): void {
  let content = fs.readFileSync(ledgerPath, 'utf-8');
  const originalLength = content.length;

  // 1. Remove all "Session Ended" entries
  content = content.replace(/\n### Session Ended \([^)]+\)\n- Reason: \w+\n/g, '');

  // 2. Keep only the last 10 agent reports
  const agentReportsMatch = content.match(/## Agent Reports\n([\s\S]*?)(?=\n## |$)/);
  if (agentReportsMatch) {
    const agentReportsSection = agentReportsMatch[0];
    const reports = agentReportsSection.match(/### [^\n]+ \(\d{4}-\d{2}-\d{2}[^)]*\)[\s\S]*?(?=\n### |\n## |$)/g);

    if (reports && reports.length > 10) {
      // Keep only the last 10 reports
      const keptReports = reports.slice(-10);
      const newAgentReportsSection = '## Agent Reports\n' + keptReports.join('');
      content = content.replace(agentReportsSection, newAgentReportsSection);
    }
  }

  // Only write if content changed
  if (content.length !== originalLength) {
    fs.writeFileSync(ledgerPath, content);
    console.error(`Pruned ledger: ${originalLength} → ${content.length} bytes`);
  }
}

function getLatestHandoff(handoffDir: string): HandoffSummary | null {
  if (!fs.existsSync(handoffDir)) return null;

  // Match both task-*.md and auto-handoff-*.md files
  const handoffFiles = fs.readdirSync(handoffDir)
    .filter(f => (f.startsWith('task-') || f.startsWith('auto-handoff-')) && f.endsWith('.md'))
    .sort((a, b) => {
      // Sort by modification time (most recent first)
      const statA = fs.statSync(path.join(handoffDir, a));
      const statB = fs.statSync(path.join(handoffDir, b));
      return statB.mtime.getTime() - statA.mtime.getTime();
    });

  if (handoffFiles.length === 0) return null;

  const latestFile = handoffFiles[0];
  const content = fs.readFileSync(path.join(handoffDir, latestFile), 'utf-8');
  const isAutoHandoff = latestFile.startsWith('auto-handoff-');

  // Extract key info from handoff based on type
  let taskNumber: string;
  let status: string;
  let summary: string;

  if (isAutoHandoff) {
    // Auto-handoff format: type: auto-handoff in frontmatter
    const typeMatch = content.match(/type:\s*auto-handoff/i);
    status = typeMatch ? 'auto-handoff' : 'unknown';

    // Extract timestamp from filename as "task number"
    const timestampMatch = latestFile.match(/auto-handoff-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})/);
    taskNumber = timestampMatch ? timestampMatch[1] : 'auto';

    // Get summary from In Progress section
    const inProgressMatch = content.match(/## In Progress\n([\s\S]*?)(?=\n## |$)/);
    summary = inProgressMatch
      ? inProgressMatch[1].trim().split('\n').slice(0, 3).join('; ').substring(0, 150)
      : 'Auto-handoff from pre-compact';
  } else {
    // Task handoff format: status: success/partial/blocked
    const taskMatch = latestFile.match(/task-(\d+)/);
    taskNumber = taskMatch ? taskMatch[1] : '??';

    const statusMatch = content.match(/status:\s*(success|partial|blocked)/i);
    status = statusMatch ? statusMatch[1] : 'unknown';

    const summaryMatch = content.match(/## What Was Done\n([\s\S]*?)(?=\n## |$)/);
    summary = summaryMatch
      ? summaryMatch[1].trim().split('\n').slice(0, 2).join('; ').substring(0, 150)
      : 'No summary available';
  }

  return {
    filename: latestFile,
    taskNumber,
    status,
    summary,
    isAutoHandoff
  };
}

// Artifact Index precedent query removed - redundant with:
// 1. Learnings now compounded into .claude/rules/ (permanent)
// 2. Ledger already provides session context
// 3. Hierarchical --learn uses handoff context at extraction time
// Kept: unmarked outcomes prompt (drives data quality)

interface UnmarkedHandoff {
  id: string;
  session_name: string;
  task_number: string | null;
  task_summary: string;
}

function getUnmarkedHandoffs(): UnmarkedHandoff[] {
  try {
    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const dbPath = path.join(projectDir, '.claude', 'cache', 'artifact-index', 'context.db');

    if (!fs.existsSync(dbPath)) {
      return [];
    }

    const result = execSync(
      `sqlite3 "${dbPath}" "SELECT id, session_name, task_number, task_summary FROM handoffs WHERE outcome = 'UNKNOWN' ORDER BY indexed_at DESC LIMIT 5"`,
      { encoding: 'utf-8', timeout: 3000 }
    );

    if (!result.trim()) {
      return [];
    }

    return result.trim().split('\n').map(line => {
      const [id, session_name, task_number, task_summary] = line.split('|');
      return { id, session_name, task_number: task_number || null, task_summary: task_summary || '' };
    });
  } catch (error) {
    return [];
  }
}

async function main() {
  const input: SessionStartInput = JSON.parse(await readStdin());
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Support both 'source' (per docs) and 'type' (legacy) fields
  const sessionType = input.source || input.type || 'startup';

  // Determine project name for claude-mem
  const projectName = getProjectName(projectDir);

  // Load claude-mem context first (works for ALL session types)
  let claudeMemContext = '';
  if (await isWorkerReady()) {
    claudeMemContext = await loadClaudeMemContext(projectName);
    if (claudeMemContext) {
      console.error(`✓ Claude-mem context loaded for ${projectName}`);
    }
  }

  // Find existing ledgers, sorted by modification time
  const ledgerDir = path.join(projectDir, 'thoughts', 'ledgers');
  let ledgerContent = '';
  let sessionName = '';
  let currentFocus = 'Unknown';
  let goalSummary = 'No goal found';
  let handoffDir = '';
  let latestHandoff: HandoffSummary | null = null;

  if (fs.existsSync(ledgerDir)) {
    const ledgerFiles = fs.readdirSync(ledgerDir)
      .filter(f => f.startsWith('CONTINUITY_CLAUDE-') && f.endsWith('.md'))
      .sort((a, b) => {
        const statA = fs.statSync(path.join(ledgerDir, a));
        const statB = fs.statSync(path.join(ledgerDir, b));
        return statB.mtime.getTime() - statA.mtime.getTime();
      });

    if (ledgerFiles.length > 0) {
      const mostRecent = ledgerFiles[0];
      const ledgerPath = path.join(ledgerDir, mostRecent);

      // Prune ledger before reading to prevent bloat
      pruneLedger(ledgerPath);

      ledgerContent = fs.readFileSync(ledgerPath, 'utf-8');

      // Extract key sections for summary
      const goalMatch = ledgerContent.match(/## Goal\n([\s\S]*?)(?=\n## |$)/);
      const nowMatch = ledgerContent.match(/- Now: ([^\n]+)/);

      goalSummary = goalMatch
        ? goalMatch[1].trim().split('\n')[0].substring(0, 100)
        : 'No goal found';

      currentFocus = nowMatch
        ? nowMatch[1].trim()
        : 'Unknown';

      sessionName = mostRecent.replace('CONTINUITY_CLAUDE-', '').replace('.md', '');

      // Check for handoff directory
      handoffDir = path.join(projectDir, 'thoughts', 'shared', 'handoffs', sessionName);
      latestHandoff = getLatestHandoff(handoffDir);

      console.error(`✓ Ledger loaded: ${sessionName} → ${currentFocus}`);
    }
  }

  // Build unified context for ALL session types
  let message = '';
  let additionalContext = '';

  // Build message based on what's available
  if (ledgerContent || claudeMemContext) {
    if (sessionName) {
      message = `[${sessionType}] Session: ${sessionName} | Focus: ${currentFocus}`;
      if (latestHandoff) {
        const handoffLabel = latestHandoff.isAutoHandoff
          ? `auto (${latestHandoff.status})`
          : `task-${latestHandoff.taskNumber} (${latestHandoff.status})`;
        message += ` | Handoff: ${handoffLabel}`;
      }
      if (claudeMemContext) {
        message += ' | Claude-mem: ✓';
      }
    } else if (claudeMemContext) {
      message = `[${sessionType}] Claude-mem context loaded for ${projectName}`;
    }
  }

  // Build additionalContext with ALL available sources (merged)
  const contextParts: string[] = [];

  // 1. Claude-Mem context (semantic memory, decisions, observations)
  if (claudeMemContext) {
    contextParts.push(`## Claude-Mem Context\n\n${claudeMemContext}`);
  }

  // 2. Continuity Ledger (current session state)
  if (ledgerContent) {
    contextParts.push(`## Continuity Ledger\n\nLoaded from: CONTINUITY_CLAUDE-${sessionName}.md\n\n${ledgerContent}`);
  }

  // 3. Latest Handoff (task context)
  if (latestHandoff && handoffDir) {
    const handoffPath = path.join(handoffDir, latestHandoff.filename);
    if (fs.existsSync(handoffPath)) {
      const handoffContent = fs.readFileSync(handoffPath, 'utf-8');
      const handoffLabel = latestHandoff.isAutoHandoff ? 'Auto-handoff' : 'Task Handoff';
      const truncatedHandoff = handoffContent.length > 2000
        ? handoffContent.substring(0, 2000) + '\n\n[... truncated, read full file if needed]'
        : handoffContent;

      contextParts.push(`## Latest ${handoffLabel}\n\nFile: ${latestHandoff.filename}\nStatus: ${latestHandoff.status}\n\n${truncatedHandoff}`);
    }
  }

  // 4. Unmarked handoffs (for clear/compact/resume only)
  if (sessionType !== 'startup') {
    const unmarkedHandoffs = getUnmarkedHandoffs();
    if (unmarkedHandoffs.length > 0) {
      let unmarkedSection = `## Unmarked Session Outcomes\n\n`;
      unmarkedSection += `Consider marking these to improve future recommendations:\n\n`;
      for (const h of unmarkedHandoffs) {
        const taskLabel = h.task_number ? `task-${h.task_number}` : 'handoff';
        const summaryPreview = h.task_summary ? h.task_summary.substring(0, 60) + '...' : '(no summary)';
        unmarkedSection += `- **${h.session_name}/${taskLabel}** (ID: \`${h.id.substring(0, 8)}\`): ${summaryPreview}\n`;
      }
      contextParts.push(unmarkedSection);
    }
  }

  // Merge all context parts
  if (contextParts.length > 0) {
    additionalContext = contextParts.join('\n\n---\n\n');
  }

  // Handle case with no context at all
  if (!message && !additionalContext) {
    if (sessionType !== 'startup') {
      console.error(`⚠ No ledger or claude-mem context found.`);
      message = `[${sessionType}] No context found. Run /continuity_ledger to track session state.`;
    }
    // For startup without any context, stay silent (normal case for new projects)
  }

  // Output with proper format per Claude Code docs
  const output: Record<string, unknown> = { result: 'continue' };

  if (message) {
    output.message = message;
    output.systemMessage = message;
  }

  if (additionalContext) {
    output.hookSpecificOutput = {
      hookEventName: 'SessionStart',
      additionalContext: additionalContext
    };
  }

  console.log(JSON.stringify(output));
}

async function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => resolve(data));
  });
}

main().catch(console.error);
