import * as fs from 'fs';
import * as path from 'path';
import * as http from 'http';
import { parseTranscript, generateAutoHandoff, TranscriptSummary, TodoItem } from './transcript-parser.js';

interface PreCompactInput {
  trigger: 'manual' | 'auto';
  session_id: string;
  transcript_path: string;
  custom_instructions?: string;
}

interface HookOutput {
  continue?: boolean;
  systemMessage?: string;
}

// Claude-Mem integration
const CLAUDE_MEM_PORT = process.env.CLAUDE_MEM_WORKER_PORT || '37777';

/**
 * Get project name from path for claude-mem
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
 * Save observation to claude-mem worker via HTTP API
 */
async function saveToClaudeMem(summary: TranscriptSummary, project: string, sessionId: string): Promise<boolean> {
  return new Promise((resolve) => {
    const url = `http://127.0.0.1:${CLAUDE_MEM_PORT}/api/observations`;

    // Build observation from transcript summary
    const inProgress = summary.lastTodos.filter(t => t.status === 'in_progress');
    const pending = summary.lastTodos.filter(t => t.status === 'pending');
    const completed = summary.lastTodos.filter(t => t.status === 'completed');

    const facts: string[] = [];

    if (summary.filesModified.length > 0) {
      facts.push(`Files modified: ${summary.filesModified.slice(0, 5).join(', ')}${summary.filesModified.length > 5 ? ` (+${summary.filesModified.length - 5} more)` : ''}`);
    }

    if (inProgress.length > 0) {
      facts.push(`In progress: ${inProgress.map(t => t.content).join('; ')}`);
    }

    if (pending.length > 0) {
      facts.push(`Pending: ${pending.length} tasks`);
    }

    if (completed.length > 0) {
      facts.push(`Completed: ${completed.length} tasks`);
    }

    if (summary.errorsEncountered.length > 0) {
      facts.push(`Errors: ${summary.errorsEncountered.length} encountered`);
    }

    const observation = {
      project,
      type: 'session-compact',
      title: `Session compacted: ${summary.lastTodos.length} todos, ${summary.filesModified.length} files`,
      summary: summary.lastAssistantMessage.substring(0, 200) || 'Auto-compact before context limit',
      facts,
      files_modified: summary.filesModified.slice(0, 10),
      session_id: sessionId
    };

    const postData = JSON.stringify(observation);

    const options: http.RequestOptions = {
      hostname: '127.0.0.1',
      port: parseInt(CLAUDE_MEM_PORT, 10),
      path: '/api/observations',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      },
      timeout: 5000
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve(res.statusCode === 200 || res.statusCode === 201);
      });
    });

    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });

    req.write(postData);
    req.end();
  });
}

/**
 * Update ledger state section with current todos from transcript
 */
function updateLedgerState(ledgerPath: string, summary: TranscriptSummary): void {
  try {
    let content = fs.readFileSync(ledgerPath, 'utf-8');

    if (summary.lastTodos.length === 0) {
      return; // No todos to update
    }

    const inProgress = summary.lastTodos.filter(t => t.status === 'in_progress');
    const pending = summary.lastTodos.filter(t => t.status === 'pending');
    const completed = summary.lastTodos.filter(t => t.status === 'completed');

    // Build new State section
    const lines: string[] = ['## State'];

    // Done items
    lines.push('- Done:');
    if (completed.length > 0) {
      completed.forEach(t => lines.push(`  - [x] ${t.content}`));
    } else {
      lines.push('  - (none this session)');
    }

    // Now (current in-progress)
    if (inProgress.length > 0) {
      lines.push(`- Now: [→] ${inProgress[0].content}`);
      // Additional in-progress items
      inProgress.slice(1).forEach(t => lines.push(`  - [→] ${t.content}`));
    } else {
      lines.push('- Now: Awaiting direction');
    }

    // Next (pending items)
    if (pending.length > 0) {
      lines.push(`- Next: ${pending[0].content}`);
      // Remaining items
      if (pending.length > 1) {
        lines.push('- Remaining:');
        pending.slice(1).forEach(t => lines.push(`  - [ ] ${t.content}`));
      }
    } else {
      lines.push('- Next: To be determined');
    }

    lines.push('');

    const newStateSection = lines.join('\n');

    // Find and replace existing State section
    const stateMatch = content.match(/## State\n[\s\S]*?(?=\n## |$)/);
    if (stateMatch) {
      content = content.replace(stateMatch[0], newStateSection.trim());
    } else {
      // No existing State section - insert after Goal section
      const goalEnd = content.match(/## Goal\n[\s\S]*?(?=\n## |$)/);
      if (goalEnd && goalEnd.index !== undefined) {
        const insertPos = goalEnd.index + goalEnd[0].length;
        content = content.slice(0, insertPos) + '\n\n' + newStateSection + content.slice(insertPos);
      } else {
        // Fallback: append to end
        content += '\n\n' + newStateSection;
      }
    }

    fs.writeFileSync(ledgerPath, content);
    console.error('✓ Ledger state updated with current todos');
  } catch (err) {
    console.error(`⚠ Failed to update ledger state: ${err}`);
  }
}

async function main() {
  const input: PreCompactInput = JSON.parse(await readStdin());
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();

  // Find existing ledger files
  const ledgerDir = path.join(projectDir, 'thoughts', 'ledgers');
  const ledgerFiles = fs.readdirSync(ledgerDir)
    .filter(f => f.startsWith('CONTINUITY_CLAUDE-') && f.endsWith('.md'));

  if (ledgerFiles.length === 0) {
    // No ledger - just remind to create one
    const output: HookOutput = {
      continue: true,
      systemMessage: '[PreCompact] No ledger found. Create one? /continuity_ledger'
    };
    console.log(JSON.stringify(output));
    return;
  }

  // Get most recent ledger
  const mostRecent = ledgerFiles.sort((a, b) => {
    const statA = fs.statSync(path.join(ledgerDir, a));
    const statB = fs.statSync(path.join(ledgerDir, b));
    return statB.mtime.getTime() - statA.mtime.getTime();
  })[0];

  const ledgerPath = path.join(ledgerDir, mostRecent);

  if (input.trigger === 'auto') {
    // Auto-compact: Use transcript parser to generate full handoff
    const sessionName = mostRecent.replace('CONTINUITY_CLAUDE-', '').replace('.md', '');
    const projectName = getProjectName(projectDir);
    let handoffFile = '';
    let savedToClaudeMem = false;

    if (input.transcript_path && fs.existsSync(input.transcript_path)) {
      // Parse transcript and generate handoff
      const summary = parseTranscript(input.transcript_path);
      const handoffContent = generateAutoHandoff(summary, sessionName);

      // Ensure handoff directory exists (thoughts/shared/handoffs is tracked in git)
      const handoffDir = path.join(projectDir, 'thoughts', 'shared', 'handoffs', sessionName);
      fs.mkdirSync(handoffDir, { recursive: true });

      // Write handoff with timestamp
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
      handoffFile = `auto-handoff-${timestamp}.md`;
      const handoffPath = path.join(handoffDir, handoffFile);
      fs.writeFileSync(handoffPath, handoffContent);

      // Phase 2: Save to claude-mem for semantic search
      savedToClaudeMem = await saveToClaudeMem(summary, projectName, input.session_id);
      if (savedToClaudeMem) {
        console.error('✓ Saved session summary to claude-mem');
      }

      // Phase 3: Update ledger state with current todos
      updateLedgerState(ledgerPath, summary);

      // Also append brief summary to ledger for visibility
      const briefSummary = generateAutoSummary(projectDir, input.session_id);
      if (briefSummary) {
        appendToLedger(ledgerPath, briefSummary);
      }
    } else {
      // Fallback: no transcript, use legacy summary
      const briefSummary = generateAutoSummary(projectDir, input.session_id);
      if (briefSummary) {
        appendToLedger(ledgerPath, briefSummary);
      }
    }

    let message = handoffFile
      ? `[PreCompact:auto] Created ${handoffFile} in thoughts/shared/handoffs/${sessionName}/`
      : `[PreCompact:auto] Session summary auto-appended to ${mostRecent}`;

    if (savedToClaudeMem) {
      message += ' | claude-mem: ✓';
    }

    const output: HookOutput = {
      continue: true,
      systemMessage: message
    };
    console.log(JSON.stringify(output));
  } else {
    // Manual compact: warn user (cannot block, just inform)
    const output: HookOutput = {
      continue: true,
      systemMessage: `[PreCompact] Consider updating ledger before compacting: /continuity_ledger\nLedger: ${mostRecent}`
    };
    console.log(JSON.stringify(output));
  }
}

function generateAutoSummary(projectDir: string, sessionId: string): string | null {
  const timestamp = new Date().toISOString();
  const lines: string[] = [];

  // Read edited files from PostToolUse cache
  const cacheDir = path.join(projectDir, '.claude', 'tsc-cache', sessionId || 'default');
  const editedFilesPath = path.join(cacheDir, 'edited-files.log');

  let editedFiles: string[] = [];
  if (fs.existsSync(editedFilesPath)) {
    const content = fs.readFileSync(editedFilesPath, 'utf-8');
    // Format: timestamp:filepath:repo per line
    editedFiles = [...new Set(
      content.split('\n')
        .filter(line => line.trim())
        .map(line => {
          const parts = line.split(':');
          // filepath is second part, remove project dir prefix
          return parts[1]?.replace(projectDir + '/', '') || '';
        })
        .filter(f => f)
    )];
  }

  // Read build attempts from .git/claude
  const gitClaudeDir = path.join(projectDir, '.git', 'claude', 'branches');
  let buildAttempts = { passed: 0, failed: 0 };

  if (fs.existsSync(gitClaudeDir)) {
    try {
      const branches = fs.readdirSync(gitClaudeDir);
      for (const branch of branches) {
        const attemptsFile = path.join(gitClaudeDir, branch, 'attempts.jsonl');
        if (fs.existsSync(attemptsFile)) {
          const content = fs.readFileSync(attemptsFile, 'utf-8');
          content.split('\n').filter(l => l.trim()).forEach(line => {
            try {
              const attempt = JSON.parse(line);
              if (attempt.type === 'build_pass') buildAttempts.passed++;
              if (attempt.type === 'build_fail') buildAttempts.failed++;
            } catch {}
          });
        }
      }
    } catch {}
  }

  // Only generate summary if we have something to report
  if (editedFiles.length === 0 && buildAttempts.passed === 0 && buildAttempts.failed === 0) {
    return null;
  }

  lines.push(`\n## Session Auto-Summary (${timestamp})`);

  if (editedFiles.length > 0) {
    lines.push(`- Files changed: ${editedFiles.slice(0, 10).join(', ')}${editedFiles.length > 10 ? ` (+${editedFiles.length - 10} more)` : ''}`);
  }

  if (buildAttempts.passed > 0 || buildAttempts.failed > 0) {
    lines.push(`- Build/test: ${buildAttempts.passed} passed, ${buildAttempts.failed} failed`);
  }

  return lines.join('\n');
}

function appendToLedger(ledgerPath: string, summary: string): void {
  try {
    let content = fs.readFileSync(ledgerPath, 'utf-8');

    // Find the "## State" section and append after "Done:" items
    const stateMatch = content.match(/## State\n/);
    if (stateMatch) {
      // Find end of Done section (before "- Now:" or "- Next:")
      const nowMatch = content.match(/(\n-\s*Now:)/);
      if (nowMatch && nowMatch.index) {
        // Insert summary before "Now:"
        content = content.slice(0, nowMatch.index) + summary + content.slice(nowMatch.index);
      } else {
        // Just append to end of State section
        const nextSection = content.indexOf('\n## ', content.indexOf('## State') + 1);
        if (nextSection > 0) {
          content = content.slice(0, nextSection) + summary + '\n' + content.slice(nextSection);
        } else {
          content += summary;
        }
      }
    } else {
      // No State section, append to end
      content += summary;
    }

    fs.writeFileSync(ledgerPath, content);
  } catch (err) {
    // Silently fail - don't break compact
  }
}

async function readStdin(): Promise<string> {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.on('data', chunk => data += chunk);
    process.stdin.on('end', () => resolve(data));
  });
}

main().catch(console.error);
