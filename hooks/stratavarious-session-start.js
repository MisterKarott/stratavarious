// stratavarious-session-start.js — SessionStart hook for StrataVarious
// Injects STRATA.md from the current project root into session context.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const MAX_LINES = 200;

function getProjectRoot(cwd) {
  try {
    const root = execSync('git rev-parse --show-toplevel', {
      cwd,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
    return root;
  } catch {
    return cwd;
  }
}

function main() {
  let input = {};
  try {
    const raw = fs.readFileSync('/dev/stdin', 'utf8');
    if (raw.trim()) input = JSON.parse(raw);
  } catch {
    process.stdout.write('{}');
    return;
  }

  const cwd = input.cwd || process.cwd();
  const projectRoot = getProjectRoot(cwd);
  const strataPath = path.join(projectRoot, 'STRATA.md');

  if (!fs.existsSync(strataPath)) {
    process.stdout.write('{}');
    return;
  }

  try {
    const content = fs.readFileSync(strataPath, 'utf8');
    const lines = content.split('\n');
    const truncated = lines.length > MAX_LINES;
    const body = truncated
      ? lines.slice(0, MAX_LINES).join('\n') + '\n\n[... truncated after 200 lines ...]'
      : content;

    const result = {
      additionalContext: `[StrataVarious] Previous session handoff loaded from STRATA.md:\n\n${body}`,
    };
    process.stdout.write(JSON.stringify(result));
  } catch {
    process.stdout.write('{}');
  }
}

main();
