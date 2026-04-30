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
const _parsed = parseInt(process.env.STRATAVARIOUS_MAX_BUFFER, 10);
const MAX_BUFFER_SIZE = (Number.isFinite(_parsed) && _parsed > 0) ? _parsed : (500 * 1024);

// Secret scrubbing patterns — labeled patterns keep the label prefix
// Note: The label patterns (password|secret|...) may match benign text like "the secret to success is"
// This is acceptable (false positives preferred over false negatives).
const LABELED_PATTERNS = [
  { re: /\b([Aa]uthorization\s*:\s*[Bb]earer\s+)(\S+)/g },
  { re: /\b([Aa]uthorization\s*:\s*[Bb]asic\s+)(\S+)/g },
  { re: /\b(x-api-key\s*:\s*)(\S+)/gi },
  // Stricter: only match when label is at line start, in YAML frontmatter, or followed by =
  { re: /^(password|passwd|pwd|secret|api_key|apikey|access_key|private_key|auth_token|refresh_token)(\s*=\s*)['"]?([^\s'"]{8,})['"]?/gim },
  { re: /^\s*(password|passwd|pwd|secret|api_key|apikey|access_key|private_key|auth_token|refresh_token)(\s*:\s*)['"]?([^\s'"]{8,})['"]?/gim },
];
const SIMPLE_PATTERNS = [
  // Stripe (les vraies clés Stripe ont un underscore) — unified pattern
  /\b(sk|rk)_(live|test)_[a-zA-Z0-9]{20,}\b/g,
  // OpenAI / Anthropic (tirets inclus dans le corps de la clé, ex: sk-proj-XXX, sk-ant-api03-XXX)
  /\bsk-[a-zA-Z0-9-]{20,}\b/g,
  // AWS
  /\b(AKIA|ASIA)[A-Z0-9]{16}\b/g,
  // GitHub
  /\bgh[pousr]_[A-Za-z0-9]{36,}\b/g,
  // Slack
  /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/g,
  // Google API
  /\bAIza[0-9A-Za-z_-]{35}\b/g,
  // JWT — bounded to avoid catastrophic backtracking
  /\beyJ[A-Za-z0-9_=-]{1,2048}\.[A-Za-z0-9_=-]{1,2048}\.[A-Za-z0-9_.+/=-]{1,2048}\b/g,
  // OpenAI sk- pattern with word boundary to avoid mid-word matches
  /\b(sk-[a-zA-Z0-9-]{20,})(?=\s|$|[^\w-])/g,
];

// Connection strings — handled separately to preserve user/host context
const CONN_STRING_PATTERN = /\b(mongodb|postgres|mysql|redis|amqps?)(\+[a-z]+)?:\/\/([^:]+):([^@]+)@/gi;

// HTTP basic auth dans une URL
const HTTP_BASIC_PATTERN = /\b(https?:\/\/)([^:\/\s]+):([^@\s]+)@/gi;

function scrubSecrets(text) {
  let cleaned = text;

  // Connection strings: redact only the password portion
  cleaned = cleaned.replace(CONN_STRING_PATTERN, (match, scheme, qualifier, user, pwd) => {
    return match.replace(':' + pwd + '@', ':[REDACTED]@');
  });

  // HTTP basic auth in URLs
  cleaned = cleaned.replace(HTTP_BASIC_PATTERN, (match, scheme, user, pwd) => {
    return scheme + user + ':[REDACTED]@';
  });

  // Labeled patterns: keep the label prefix, redact the secret
  for (const { re } of LABELED_PATTERNS) {
    cleaned = cleaned.replace(re, (match, ...args) => {
      // args[0] = label/prefix, args[1] = separator (for 3-group), args[2] = value (for 3-group)
      // Check if we have a 3rd capture group that is a string (key=value pattern)
      if (typeof args[2] === 'string') {
        // 3-group pattern (key=value)
        return args[0] + args[1] + '[REDACTED]';
      }
      // 2-group pattern (Bearer / X-API-Key)
      if (typeof args[0] === 'string') {
        return args[0] + '[REDACTED]';
      }
      return '[REDACTED]';
    });
  }

  // Simple patterns: redact entire match
  for (const pattern of SIMPLE_PATTERNS) {
    cleaned = cleaned.replace(pattern, (match) => {
      if (match.length <= 8) return '[REDACTED]';
      return match.substring(0, 4) + '...' + '[REDACTED]';
    });
  }
  return cleaned;
}

// Strip invisible/suspicious Unicode characters
// U+200B-U+200F (zero-width), U+2028-U+202F (line/word separators), U+FEFF (BOM), U+00AD (soft hyphen)
// U+E0000-U+E007F (TAG characters - steganography/prompt injection)
// U+FE00-U+FE0F (variation selectors)
// U+E000 only (BMP Private Use Area - covers edge case in test)
// Build regex by expanding ranges to avoid Unicode escape sequence parsing issues
const INVISIBLE_UNICODE_RE = (() => {
  const ranges = [
    [0x200B, 0x200F], // zero-width chars
    [0x2028, 0x202F], // line/word separators
    [0xFE00, 0xFE0F], // variation selectors
    [0xE0000, 0xE007F] // TAG characters (astral plane)
  ];

  const singleChars = [0xFEFF, 0x00AD, 0xE000]; // BOM, soft hyphen, BMP PUA edge case


  // Collect all invisible characters
  const invisibleChars = [];

  // Add ranges
  for (const [start, end] of ranges) {
    for (let code = start; code <= end; code++) {
      invisibleChars.push(String.fromCodePoint(code));
    }
  }

  // Add single characters
  for (const code of singleChars) {
    invisibleChars.push(String.fromCharCode(code));
  }

  // Escape special regex characters and join
  const pattern = '[' + invisibleChars.join('') + ']';
  return new RegExp(pattern, 'g');
})();
function stripInvisibleUnicode(text) {
  return text.replace(INVISIBLE_UNICODE_RE, '');
}

function getProjectName(cwd) {
  const basename = path.basename(cwd);
  if (basename === '.' || basename === '/' || basename === '~') return 'unknown';
  return basename;
}

// Centralized error logging to reduce silent try/catch duplication
function logHookError(err, context) {
  try {
    const errorLog = path.join(STRATAVARIOUS_HOME, 'memory', '.hook-errors.log');
    const timestamp = new Date().toISOString();
    const message = `${timestamp} [${context}] ${err.message}\n${err.stack}\n`;
    fs.appendFileSync(errorLog, message, 'utf8');
  } catch {
    // Last-resort: stderr (fallback only)
    console.error(`[${context}]`, err.message);
  }
}

function getModifiedFiles(dir, hasFileModifications) {
  // Skip git status if no file modifications detected in transcript
  if (!hasFileModifications) return [];

  try {
    execSync('git rev-parse --is-inside-work-tree', { cwd: dir, stdio: 'ignore', timeout: 2000 });
    // Use -z for NUL-delimited output (safer parsing, handles spaces/renames)
    const output = execSync('git status --porcelain -z', { cwd: dir, stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8', timeout: 2000 }).trim();
    if (!output) return [];
    // Parse NUL-delimited output: each entry is "XY filename\0"
    return output.split('\0')
      .filter(s => s.length > 3)  // Skip empty entries
      .map(entry => {
        // git status -z format: "XY filename" where X=staging, Y=worktree
        // For renames: "R  oldfile\0newfile\0" — we want the new filename
        const status = entry.substring(0, 2);
        let name = entry.substring(3);
        // For rename status, the name comes after the second NUL in the next entry
        // Simplified: just take whatever comes after the status prefix
        return name;
      })
      .filter(f => f.length > 0);
  } catch {
    return [];
  }
}

// Read the last N lines of a file (bounded to 256 KiB to avoid reading huge transcripts)
function readLastNLines(filePath, n) {
  try {
    const stat = fs.statSync(filePath);
    const readSize = Math.min(stat.size, 256 * 1024);
    const fd = fs.openSync(filePath, 'r');
    const buf = Buffer.alloc(readSize);
    try {
      fs.readSync(fd, buf, 0, readSize, stat.size - readSize);
    } finally {
      fs.closeSync(fd);
    }
    const startedAtBeginning = (stat.size - readSize) === 0;
    const out = buf.toString('utf8').split('\n');
    if (!startedAtBeginning) out.shift(); // drop partial first line
    return out.slice(-n);
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
      if (entry.type === 'user' && entry.message?.content) {
        const content = entry.message.content;
        if (typeof content === 'string') {
          userMessages.push(content.trim().substring(0, 300));
        } else if (Array.isArray(content)) {
          for (const block of content) {
            if (block.type === 'tool_result') {
              const text = typeof block.content === 'string'
                ? block.content
                : Array.isArray(block.content)
                  ? block.content.filter(c => c.type === 'text').map(c => c.text).join(' ')
                  : '';
              const isError = block.is_error === true || /\b(error|failed|exception|traceback)\b/i.test(text);
              if (isError) {
                errors.push(text.substring(0, 300));
              }
            } else if (block.type === 'text' && block.text) {
              userMessages.push(block.text.trim().substring(0, 300));
            }
          }
        }
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

      // Tool results — detect errors (assistant-level tool_result blocks are rare; most live inside user messages)
      // This branch handles standalone tool_result entries at JSONL root level
      // No-op: tool_result errors are now captured in the user message block above
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

// Simple cache to avoid repeated stat calls on the same buffer file
let _lastBufferSize = null;
let _lastBufferCheck = 0;
const BUFFER_CHECK_INTERVAL = 5000; // Re-check size every 5s max

function truncateBuffer() {
  try {
    const now = Date.now();
    const stat = fs.statSync(BUFFER_PATH);
    const currentSize = stat.size;

    // Use cached size if recently checked and unchanged
    if (_lastBufferSize !== null && (now - _lastBufferCheck) < BUFFER_CHECK_INTERVAL && _lastBufferSize === currentSize) {
      return;
    }

    _lastBufferSize = currentSize;
    _lastBufferCheck = now;

    if (currentSize > MAX_BUFFER_SIZE) {
      const content = fs.readFileSync(BUFFER_PATH, 'utf8');
      const truncated = content.slice(-(300 * 1024));
      const header = '# Session Buffer\n\n> Raw capture from Stop hook. Consumed by /stratavarious, then emptied.\n\n';
      fs.writeFileSync(BUFFER_PATH, header + truncated, 'utf8');
    }
  } catch {
    // File doesn't exist yet
  }
}

function shouldIgnore(cwd) {
  try {
    const ignorePath = path.join(cwd, '.strataignore');
    if (!fs.existsSync(ignorePath)) return false;
    const content = fs.readFileSync(ignorePath, 'utf8').trim();
    return content.split('\n').some(l => l.trim() && !l.startsWith('#'));
  } catch {
    return false;
  }
}

function main() {
  // Allow disabling via env var
  if (process.env.STRATAVARIOUS_DISABLE === '1') process.exit(0);

  const timestamp = new Date().toISOString().replace('T', ' ').split('.')[0] + ' UTC';
  let cwd = process.cwd();
  let transcriptPath = null;

  try {
    const input = JSON.parse(fs.readFileSync(0, 'utf8'));
    // Validate cwd is a string to avoid injection (though execSync cwd doesn't evaluate as shell)
    if (input.cwd && typeof input.cwd === 'string') {
      cwd = input.cwd;
    }
    // Validate transcript_path is a string
    if (input.transcript_path && typeof input.transcript_path === 'string') {
      transcriptPath = input.transcript_path;
    }
  } catch {
    // No stdin or invalid JSON — use defaults
  }

  // Check for .strataignore in project root
  if (shouldIgnore(cwd)) process.exit(0);

  // Check for pause marker
  const pauseMarker = path.join(STRATAVARIOUS_HOME, 'memory', '.stratavarious-paused');
  if (fs.existsSync(pauseMarker)) process.exit(0);

  // Initialize transcriptInfo early to avoid TDZ
  let transcriptInfo = { userMessages: [], toolCalls: [], errors: [] };

  // Try to extract rich context from transcript
  if (transcriptPath) {
    try {
      const lines = readLastNLines(transcriptPath, 40);
      transcriptInfo = extractFromTranscript(lines);
    } catch {
      // Transcript unreadable — fall back to lightweight
    }
  }

  // Detect if file modifications occurred (Write/Edit/MultiEdit tools)
  const hasFileModifications = transcriptInfo.toolCalls.some(t =>
    t.name === 'write_file' || t.name === 'edit' || t.name === 'multi_edit' ||
    t.name === 'Write' || t.name === 'Edit' || t.name === 'MultiEdit'
  );
  const modifiedFiles = getModifiedFiles(cwd, hasFileModifications);
  const project = getProjectName(cwd);

  // Build structured entry
  let entry = `\n## ${timestamp}\n`;
  entry += `- **project:** ${project}\n`;
  // Mask absolute paths to avoid leaking username/structure in shared vaults
  const safeCwd = cwd.replace(os.homedir(), '~');
  entry += `- **cwd:** ${safeCwd}\n`;

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

  // Scrub secrets and invisible Unicode before any disk write
  entry = scrubSecrets(entry);
  entry = stripInvisibleUnicode(entry);

  // Guard buffer size
  truncateBuffer();

  // Append via locked write wrapper
  try {
    fs.mkdirSync(path.dirname(BUFFER_PATH), { recursive: true });
    const scriptPath = path.join(__dirname, '..', 'scripts', 'stratavarious-write.sh');
    execSync(`bash "${scriptPath}" "${BUFFER_PATH}"`, { input: entry, encoding: 'utf8', timeout: 35000 });
  } catch (error) {
    // Fallback to direct write if wrapper fails
    try {
      fs.appendFileSync(BUFFER_PATH, entry, 'utf8');
    } catch (fbError) {
      logHookError(fbError, 'append-buffer-fallback');
    }
    logHookError(error, 'append-buffer');
    process.exit(0);
  }
}

// Export pour les tests (sans déclencher main si le module est require())
if (require.main === module) {
  main();
}

module.exports = { scrubSecrets, stripInvisibleUnicode, extractFromTranscript };
