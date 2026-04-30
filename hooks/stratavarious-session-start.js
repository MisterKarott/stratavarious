// stratavarious-session-start.js — SessionStart hook for StrataVarious
// Injects STRATA.md from the current project root into session context.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const MAX_LINES = 200;
const MAX_FILE_SIZE = 64 * 1024; // 64 KB max read to avoid loading huge STRATA.md files

function getProjectRoot(cwd) {
  // First, check if STRATA.md exists in current directory
  const localStrata = path.join(cwd, 'STRATA.md');
  if (fs.existsSync(localStrata)) {
    return cwd;
  }

  // Otherwise, use git to find the repo root (but only if needed)
  try {
    const root = execSync('git rev-parse --show-toplevel', {
      cwd,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 2000, // Add timeout to avoid hanging
    }).trim();
    return root;
  } catch {
    return cwd;
  }
}

function loadProfile() {
  try {
    const home = process.env.STRATAVARIOUS_HOME || path.join(os.homedir(), '.claude', 'workspace', 'stratavarious');
    const profilePath = path.join(home, 'memory', 'profile.md');
    if (fs.existsSync(profilePath)) {
      const content = fs.readFileSync(profilePath, 'utf8').trim();
      if (content.length > 50) return content;
    }
  } catch { /* profile unreadable — skip */ }
  return null;
}

function main() {
  let input = {};
  try {
    const raw = fs.readFileSync(0, 'utf8');
    if (raw.trim()) input = JSON.parse(raw);
  } catch {
    process.stdout.write('{}');
    return;
  }

  const cwd = input.cwd || process.cwd();
  const projectRoot = getProjectRoot(cwd);
  const strataPath = path.join(projectRoot, 'STRATA.md');
  const profile = loadProfile();

  if (!fs.existsSync(strataPath)) {
    if (profile) {
      process.stdout.write(JSON.stringify({
        additionalContext: '[StrataVarious] User profile loaded:\n\n' + profile,
      }));
    } else {
      process.stdout.write('{}');
    }
    return;
  }

  try {
    // Check file size before reading to avoid loading huge STRATA.md files
    const stat = fs.statSync(strataPath);
    if (stat.size > MAX_FILE_SIZE) {
      // File too large, read only the first 64 KB
      const buffer = Buffer.alloc(MAX_FILE_SIZE);
      const fd = fs.openSync(strataPath, 'r');
      try {
        fs.readSync(fd, buffer, 0, MAX_FILE_SIZE, 0);
      } finally {
        fs.closeSync(fd);
      }
      const content = buffer.toString('utf8');
      const lines = content.split('\n');
      const truncated = lines.length > MAX_LINES;
      const body = truncated
        ? lines.slice(0, MAX_LINES).join('\n') + '\n\n[... truncated after 200 lines ...]'
        : content;

      let additionalContext = `[StrataVarious] Previous session handoff loaded from STRATA.md:\n\n${body}`;
      if (profile) additionalContext += '\n\n[StrataVarious] User profile loaded:\n\n' + profile;
      process.stdout.write(JSON.stringify({ additionalContext }));
      return;
    }

    // File is within size bounds, read normally
    const content = fs.readFileSync(strataPath, 'utf8');
    const lines = content.split('\n');
    const truncated = lines.length > MAX_LINES;
    const body = truncated
      ? lines.slice(0, MAX_LINES).join('\n') + '\n\n[... truncated after 200 lines ...]'
      : content;

    let additionalContext = `[StrataVarious] Previous session handoff loaded from STRATA.md:\n\n${body}`;
    if (profile) additionalContext += '\n\n[StrataVarious] User profile loaded:\n\n' + profile;
    process.stdout.write(JSON.stringify({ additionalContext }));
  } catch {
    process.stdout.write('{}');
  }
}

main();
