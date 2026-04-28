// stratavarious-stop.js — Enriched Stop hook for StrataVarious
// Captures session data after each Claude response.
// Reads transcript JSONL to extract: user intent, tools used, errors, files touched.
// Falls back to lightweight metadata if transcript is unavailable.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const STRATAVARIOUS_HOME = process.env.STRATAVARIOUS_HOME || path.join(os.homedir(), '.claude', 'workspace', 'stratavarious');
const BUFFER_PATH = path.join(STRATAVARIOUS_HOME, 'memory', 'session-buffer.md');
const MAX_BUFFER_SIZE = 500 * 1024; // 500KB

function getProjectName(cwd) {
  const basename = path.basename(cwd);
  if (basename === '.' || basename === '/' || basename === '~') return 'unknown';
  return basename;
}

function getModifiedFiles(dir) {
  try {
    execSync('git rev-parse --is-inside-work-tree', { cwd: dir, stdio: 'ignore' });
    const output = execSync('git status --porcelain', { cwd: dir, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8' }).trim();
    if (!output) return [];
    return output.split('\n')
      .map(line => line.substring(3).trim())
      .filter(f => f.length > 0);
  } catch {
    return [];
  }
}

// Read the last N lines of a file efficiently
function readLastNLines(filePath, n) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.trim().split('\n');
    return lines.slice(-n);
  } catch {
    return [];
  }
}

// Extract structured info from transcript JSONL lines
function extractFromTranscript(lines) {
  const userMessages = [];
  const toolCalls = [];
  const errors = [];

  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const entry = JSON.parse(line);

      // User messages — capture intent
      if (entry.type === 'human' && entry.message?.content) {
        const text = typeof entry.message.content === 'string'
          ? entry.message.content
          : Array.isArray(entry.message.content)
            ? entry.message.content.filter(c => c.type === 'text').map(c => c.text).join(' ')
            : '';
        if (text.trim()) userMessages.push(text.trim().substring(0, 300));
      }

      // Assistant tool calls — capture what was done
      if (entry.type === 'assistant' && Array.isArray(entry.message?.content)) {
        for (const block of entry.message.content) {
          if (block.type === 'tool_use' && block.name) {
            const summary = { name: block.name };
            // Extract key paths from common tools
            if (block.input?.file_path) summary.path = block.input.file_path;
            else if (block.input?.command) summary.cmd = block.input.command.substring(0, 150);
            toolCalls.push(summary);
          }
        }
      }

      // Tool results — detect errors
      if (entry.type === 'tool_result') {
        const text = typeof entry.content === 'string'
          ? entry.content
          : Array.isArray(entry.content)
            ? entry.content.filter(c => c.type === 'text').map(c => c.text).join(' ')
            : '';
        if (text && (text.includes('Error') || text.includes('error') || text.includes('FAILED') || text.includes('failed'))) {
          errors.push(text.substring(0, 300));
        }
      }
    } catch {
      // Skip malformed lines
    }
  }

  return {
    userMessages: userMessages.slice(-3),
    toolCalls: toolCalls.slice(-15),
    errors: errors.slice(-3)
  };
}

function truncateBuffer() {
  try {
    const stat = fs.statSync(BUFFER_PATH);
    if (stat.size > MAX_BUFFER_SIZE) {
      const content = fs.readFileSync(BUFFER_PATH, 'utf8');
      const truncated = content.slice(-(300 * 1024));
      const header = '# Session Buffer\n\n> Raw capture from Stop hook. Consumed by /stratavarious, then emptied.\n\n';
      fs.writeFileSync(BUFFER_PATH, header + truncated, 'utf8');
    }
  } catch {
    // File doesn't exist yet
  }
}

function main() {
  const timestamp = new Date().toISOString().replace('T', ' ').split('.')[0] + ' UTC';
  let cwd = process.cwd();
  let transcriptPath = null;

  try {
    const input = JSON.parse(fs.readFileSync(0, 'utf8'));
    cwd = input.cwd || process.cwd();
    transcriptPath = input.transcript_path || null;
  } catch {
    // No stdin or invalid JSON — use defaults
  }

  const modifiedFiles = getModifiedFiles(cwd);
  const project = getProjectName(cwd);

  // Try to extract rich context from transcript
  let transcriptInfo = { userMessages: [], toolCalls: [], errors: [] };
  if (transcriptPath) {
    try {
      const lines = readLastNLines(transcriptPath, 40);
      transcriptInfo = extractFromTranscript(lines);
    } catch {
      // Transcript unreadable — fall back to lightweight
    }
  }

  // Build structured entry
  let entry = `\n## ${timestamp}\n`;
  entry += `- **projet:** ${project}\n`;
  entry += `- **cwd:** ${cwd}\n`;

  // User intent (most recent user message)
  if (transcriptInfo.userMessages.length > 0) {
    const intent = transcriptInfo.userMessages[transcriptInfo.userMessages.length - 1];
    entry += `- **intent:** ${intent}\n`;
  }

  // Files modified (from git)
  if (modifiedFiles.length > 0) {
    entry += `- **files:** ${modifiedFiles.join(', ')}\n`;
  }

  // Tools used (unique tool names)
  if (transcriptInfo.toolCalls.length > 0) {
    const tools = [...new Set(transcriptInfo.toolCalls.map(t => {
      if (t.path) return `${t.name}(${path.basename(t.path)})`;
      if (t.cmd) return `${t.name}(${t.cmd.substring(0, 50)})`;
      return t.name;
    }))].join(', ');
    entry += `- **actions:** ${tools}\n`;
  }

  // Errors detected
  if (transcriptInfo.errors.length > 0) {
    entry += `- **errors:** ${transcriptInfo.errors[0]}\n`;
  }

  entry += '\n';

  // Guard buffer size
  truncateBuffer();

  // Append
  try {
    fs.mkdirSync(path.dirname(BUFFER_PATH), { recursive: true });
    fs.appendFileSync(BUFFER_PATH, entry, 'utf8');
  } catch (error) {
    // Silent fail — hook must not block Claude
    process.exit(0);
  }
}

main();
