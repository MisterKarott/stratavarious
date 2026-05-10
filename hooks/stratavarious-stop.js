// stratavarious-stop.js — Enriched Stop hook for StrataVarious
// Captures session data after each Claude response.
// Reads transcript JSONL to extract: user intent, tools used, errors, files touched.
// Falls back to lightweight metadata if transcript is unavailable.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

// Canonicalize STRATAVARIOUS_HOME: resolve to absolute path, strip NUL, reject relative.
const _rawHome = process.env.STRATAVARIOUS_HOME || path.join(os.homedir(), '.claude', 'workspace', 'stratavarious');
const STRATAVARIOUS_HOME = path.resolve(_rawHome).replace(/\0/g, '');
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
  // AWS
  /\b(AKIA|ASIA)[A-Z0-9]{16}\b/g,
  // GitHub classic PAT
  /\bgh[pousr]_[A-Za-z0-9]{36,}\b/g,
  // GitHub fine-grained PAT — https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
  /\bgithub_pat_[A-Za-z0-9_]{20,}\b/g,
  // Slack
  /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/g,
  // Google API key
  /\bAIza[0-9A-Za-z_-]{35}\b/g,
  // Google OAuth access token — https://developers.google.com/identity/protocols/oauth2
  /\bya29\.[A-Za-z0-9_-]{20,}\b/g,
  // JWT — bounded to avoid catastrophic backtracking
  /\beyJ[A-Za-z0-9_=-]{1,2048}\.[A-Za-z0-9_=-]{1,2048}\.[A-Za-z0-9_.+/=-]{1,2048}\b/g,
  // OpenAI / Anthropic sk- prefix — https://docs.anthropic.com/en/api/getting-started
  /\b(sk-ant-[a-zA-Z0-9_-]{20,})(?=\s|$|[^\w-])/g,
  /\b(sk-[a-zA-Z0-9-]{20,})(?=\s|$|[^\w-])/g,
];

// Strict-mode labeled patterns: same as LABELED_PATTERNS but anchors relaxed to match mid-line.
// Opt-in via STRATAVARIOUS_STRICT_SCRUB=1. Higher false-positive rate.
// Risk: "I use api_key=none as placeholder" gets redacted. Prefer default mode in shared vaults.
const STRICT_LABELED_PATTERNS = [
  { re: /\b([Aa]uthorization\s*:\s*[Bb]earer\s+)(\S+)/g },
  { re: /\b([Aa]uthorization\s*:\s*[Bb]asic\s+)(\S+)/g },
  { re: /\b(x-api-key\s*:\s*)(\S+)/gi },
  // Mid-line match: drops ^ anchor, matches password/secret/etc. anywhere in line
  { re: /(password|passwd|pwd|secret|api_key|apikey|access_key|private_key|auth_token|refresh_token)(\s*=\s*)['"]?([^\s'"]{8,})['"]?/gim },
  { re: /\s*(password|passwd|pwd|secret|api_key|apikey|access_key|private_key|auth_token|refresh_token)(\s*:\s*)['"]?([^\s'"]{8,})['"]?/gim },
];

// Shannon entropy: H = -sum(p * log2(p)) over unique chars
// Used for entropy scan (opt-in via STRATAVARIOUS_ENTROPY_SCAN=1).
function shannonEntropy(str) {
  const freq = {};
  for (let i = 0; i < str.length; i++) {
    const c = str[i];
    freq[c] = (freq[c] || 0) + 1;
  }
  let h = 0;
  const len = str.length;
  const keys = Object.keys(freq);
  for (let i = 0; i < keys.length; i++) {
    const p = freq[keys[i]] / len;
    h -= p * Math.log2(p);
  }
  return h;
}

// Regex for high-entropy candidate strings: only chars common in tokens/keys
const HIGH_ENTROPY_RE = /[a-zA-Z0-9+/=_-]{20,}/g;

// Connection strings — handled separately to preserve user/host context
const CONN_STRING_PATTERN = /\b(mongodb|postgres|mysql|redis|amqps?)(\+[a-z]+)?:\/\/([^:]+):([^@]+)@/gi;

// HTTP basic auth dans une URL
const HTTP_BASIC_PATTERN = /\b(https?:\/\/)([^:\/\s]+):([^@\s]+)@/gi;

function scrubSecrets(text, opts) {
  const strictMode = (opts && opts.strict) || process.env.STRATAVARIOUS_STRICT_SCRUB === '1';
  const entropyMode = (opts && opts.entropy) || process.env.STRATAVARIOUS_ENTROPY_SCAN === '1';
  const _rawThreshold = parseFloat(process.env.STRATAVARIOUS_ENTROPY_THRESHOLD || '');
  const entropyThreshold = (isFinite(_rawThreshold) && _rawThreshold > 0) ? _rawThreshold : 4.5;

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
  const activeLabeled = strictMode ? STRICT_LABELED_PATTERNS : LABELED_PATTERNS;
  for (const { re } of activeLabeled) {
    cleaned = cleaned.replace(re, (match, ...args) => {
      // args[0] = label/prefix, args[1] = separator (for 3-group), args[2] = value (for 3-group)
      if (typeof args[2] === 'string') {
        return args[0] + args[1] + '[REDACTED]';
      }
      if (typeof args[0] === 'string') {
        return args[0] + '[REDACTED]';
      }
      return '[REDACTED]';
    });
  }

  // Simple patterns: redact entire match
  for (const pattern of SIMPLE_PATTERNS) {
    cleaned = cleaned.replace(pattern, (match) => match.substring(0, 4) + '...' + '[REDACTED]');
  }

  // Entropy scan (opt-in): redact high-entropy strings that look like tokens
  if (entropyMode) {
    cleaned = cleaned.replace(HIGH_ENTROPY_RE, (match) => {
      if (shannonEntropy(match) > entropyThreshold) {
        return match.substring(0, 4) + '...' + '[REDACTED-ENTROPY]';
      }
      return match;
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
    // Mask homedir in messages/stack traces to avoid leaking username/paths.
    const home = os.homedir();
    const mask = (s) => (s || '').split(home).join('~');
    const message = `${timestamp} [${context}] ${mask(err.message)}\n${mask(err.stack)}\n`;
    fs.appendFileSync(errorLog, message, 'utf8');
  } catch {
    // Last-resort: stderr (fallback only)
    console.error(`[${context}]`, err.message);
  }
}

function getModifiedFiles(_dir, _hasFileModifications) {
  // File list derived from transcript tool calls only — no git dependency
  return [];
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
      // Atomic rewrite using mkdir-based lock (same as write.sh, no flock needed)
      const lockDir = path.join(path.dirname(BUFFER_PATH), '.vault.lock.d');
      const lockPidFile = path.join(lockDir, 'pid');
      const tmpPath = BUFFER_PATH + '.tmp.' + process.pid;
      const header = '# Session Buffer\n\n> Raw capture from Stop hook. Consumed by /stratavarious, then emptied.\n\n';

      for (let attempt = 0; attempt < 30; attempt++) {
        try {
          fs.mkdirSync(lockDir, { recursive: false }); // atomic, fails if exists
          fs.writeFileSync(lockPidFile, String(process.pid));
          // Lock acquired — perform truncation
          const content = fs.readFileSync(BUFFER_PATH, 'utf8');
          const truncated = header + content.slice(-307200);
          fs.writeFileSync(tmpPath, truncated, 'utf8');
          fs.renameSync(tmpPath, BUFFER_PATH); // atomic rename
          // Cleanup lock
          try { fs.rmSync(lockPidFile, { force: true }); } catch {}
          try { fs.rmdirSync(lockDir); } catch {}
          break;
        } catch (err) {
          if (err.code === 'EEXIST') {
            // Lock held — check if stale
            try {
              const pid = parseInt(fs.readFileSync(lockPidFile, 'utf8'), 10);
              if (pid > 0) process.kill(pid, 0); // throws if dead
            } catch {
              // Stale lock — remove and retry
              try { fs.rmSync(lockPidFile, { force: true }); } catch {}
              try { fs.rmdirSync(lockDir); } catch {}
              continue;
            }
            // Lock held by live process — wait
            if (attempt >= 29) break;
            try { execFileSync('sleep', ['1']); } catch {}
            continue;
          }
          break; // other error — give up
        }
      }
    }
  } catch {
    // File doesn't exist yet
  }
}

// Honor .strataignore only if it contains an explicit opt-out token.
// Prevents an attacker-planted file from silently disabling the hook.
function shouldIgnore(cwd) {
  try {
    const ignorePath = path.join(cwd, '.strataignore');
    const lst = fs.lstatSync(ignorePath);
    if (lst.isSymbolicLink()) return false;
    const content = fs.readFileSync(ignorePath, 'utf8');
    const optOut = content.split('\n').some(l => l.trim() === 'disable' || l.trim() === 'ignore');
    if (optOut) {
      logHookError(new Error(`opt-out via .strataignore at ${ignorePath}`), 'strataignore');
    }
    return optOut;
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
    // Cap stdin to 1 MiB to avoid OOM on adversarial input
    const STDIN_MAX = 1024 * 1024;
    const buf = Buffer.alloc(STDIN_MAX);
    let read = 0;
    try {
      read = fs.readSync(0, buf, 0, STDIN_MAX, null);
    } catch { /* EAGAIN / no stdin */ }
    const input = JSON.parse(buf.slice(0, read).toString('utf8'));
    // Validate cwd is a string to avoid injection (though execSync cwd doesn't evaluate as shell)
    if (input.cwd && typeof input.cwd === 'string') {
      cwd = input.cwd;
    }
    // Validate transcript_path: must be a string, absolute, .jsonl, no traversal,
    // and located under the Claude projects dir (where the harness writes them).
    if (input.transcript_path && typeof input.transcript_path === 'string') {
      const tp = input.transcript_path;
      const expectedRoot = path.join(os.homedir(), '.claude', 'projects');
      const resolved = path.resolve(tp);
      if (
        path.isAbsolute(tp) &&
        resolved === tp &&
        !tp.includes('\0') &&
        tp.endsWith('.jsonl') &&
        resolved.startsWith(expectedRoot + path.sep)
      ) {
        transcriptPath = resolved;
      }
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

  // Derive modified files from transcript tool calls (no git dependency)
  const FILE_TOOLS = new Set(['write_file', 'edit', 'multi_edit', 'Write', 'Edit', 'MultiEdit']);
  const modifiedFiles = [...new Set(
    transcriptInfo.toolCalls
      .filter(t => FILE_TOOLS.has(t.name) && t.path)
      .map(t => path.basename(t.path))
  )];
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

  // Strip invisible Unicode FIRST so secrets can't bypass scrubbing via ZWSP/etc.
  entry = stripInvisibleUnicode(entry);
  entry = scrubSecrets(entry);

  // Guard buffer size
  truncateBuffer();

  // Append via locked write wrapper. Refuse to follow symlinks to prevent
  // attacker-controlled redirects to sensitive files.
  try {
    fs.mkdirSync(path.dirname(BUFFER_PATH), { recursive: true });
    try {
      const lst = fs.lstatSync(BUFFER_PATH);
      if (lst.isSymbolicLink()) {
        logHookError(new Error(`refusing symlink: ${BUFFER_PATH}`), 'symlink-guard');
        process.exit(0);
      }
    } catch { /* file doesn't exist yet — fine */ }

    const scriptPath = path.join(__dirname, '..', 'scripts', 'stratavarious-write.sh');
    execFileSync('bash', [scriptPath, BUFFER_PATH], { input: entry, encoding: 'utf8', timeout: 35000 });
  } catch (error) {
    // Fallback to direct write if wrapper fails — open with O_NOFOLLOW
    try {
      const fd = fs.openSync(BUFFER_PATH, fs.constants.O_WRONLY | fs.constants.O_APPEND | fs.constants.O_CREAT | fs.constants.O_NOFOLLOW, 0o600);
      try { fs.writeSync(fd, entry, null, 'utf8'); } finally { fs.closeSync(fd); }
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

module.exports = { scrubSecrets, stripInvisibleUnicode, extractFromTranscript, shannonEntropy };
