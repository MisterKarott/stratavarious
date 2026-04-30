#!/usr/bin/env node
// stratavarious-semantique-dedup.js — Semantic deduplication via Claude API
// Reads pairs of similar vault notes from stdin (tab-separated paths)
// Asks Claude to determine if they cover the same topic
// Outputs merge recommendations
// Requires ANTHROPIC_API_KEY environment variable

'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');

const API_KEY = process.env.ANTHROPIC_API_KEY;
const API_MODEL = process.env.ANTHROPIC_MODEL || 'claude-haiku-4-5-20251001';
const API_HOST = process.env.ANTHROPIC_BASE_URL
  ? process.env.ANTHROPIC_BASE_URL.replace(/\/$/, '')
  : 'https://api.anthropic.com';
const MAX_CONTENT_LENGTH = 2000; // chars per note sent to API
const BATCH_SIZE = 5; // max pairs per API call

function readNote(filePath, maxLen) {
  try {
    let content = fs.readFileSync(filePath, 'utf8');
    // Strip frontmatter
    content = content.replace(/^---\n[\s\S]*?\n---\n/, '');
    if (content.length > maxLen) {
      content = content.slice(0, maxLen) + '\n[... truncated ...]';
    }
    return content;
  } catch {
    return '(unreadable)';
  }
}

function callClaudeAPI(prompt) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      model: API_MODEL,
      max_tokens: 1024,
      messages: [{ role: 'user', content: prompt }],
    });

    const url = new URL(API_HOST + '/v1/messages');
    const options = {
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY,
        'anthropic-version': '2023-06-01',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 30000,
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.content && parsed.content[0]) {
            resolve(parsed.content[0].text);
          } else {
            reject(new Error('Unexpected API response format'));
          }
        } catch {
          reject(new Error('Failed to parse API response'));
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('API timeout')); });
    req.write(body);
    req.end();
  });
}

async function processBatch(pairs) {
  const promptParts = pairs.map((pair, i) => {
    const contentA = readNote(pair[0], MAX_CONTENT_LENGTH);
    const contentB = readNote(pair[1], MAX_CONTENT_LENGTH);
    return `--- Pair ${i + 1} ---\nFile A: ${path.basename(pair[0])}\n${contentA}\n\nFile B: ${path.basename(pair[1])}\n${contentB}`;
  });

  const prompt = `You are a vault deduplication assistant. For each pair of notes below, determine if they cover the same topic and should be merged.

Rules:
- MERGE only if both notes contain substantially overlapping information about the same topic
- SKIP if they are related but cover different aspects, or if merging would lose distinct information
- The keeper should be the more comprehensive note

For each pair, respond with EXACTLY one line in this format:
MERGE:keeper_path|merge_source_path
or:
SKIP

${promptParts.join('\n\n')}

Respond with one line per pair, no other text.`;

  try {
    const response = await callClaudeAPI(prompt);
    return response.trim().split('\n').filter(l => l.trim());
  } catch (err) {
    process.stderr.write(`Semantic dedup API error: ${err.message}\n`);
    return [];
  }
}

function mergeNotes(keeperPath, sourcePath) {
  try {
    let keeper = fs.readFileSync(keeperPath, 'utf8');
    let source = fs.readFileSync(sourcePath, 'utf8');

    // Strip frontmatter from source, keep body
    const sourceBody = source.replace(/^---\n[\s\S]*?\n---\n/, '');
    if (sourceBody.trim().length === 0) return;

    // Append source content to keeper
    keeper = keeper.trimEnd() + '\n\n---\nMerged from: ' + path.basename(sourcePath) + '\n---\n' + sourceBody.trim();
    fs.writeFileSync(keeperPath, keeper, 'utf8');

    // Add deprecated frontmatter to source
    source = source.replace(
      /^(---\n)/,
      '$1deprecated: true\ndeprecated_reason: Merged into ' + path.basename(keeperPath) + ' on ' + new Date().toISOString().slice(0, 10) + '\n'
    );
    fs.writeFileSync(sourcePath, source, 'utf8');

    console.log('  MERGED: ' + path.basename(sourcePath) + ' → ' + path.basename(keeperPath));
  } catch (err) {
    process.stderr.write(`Merge error: ${err.message}\n`);
  }
}

async function main() {
  if (!API_KEY) {
    process.exit(0); // silent exit if no API key
  }

  const input = fs.readFileSync(0, 'utf8').trim();
  if (!input) process.exit(0);

  const pairs = input.split('\n')
    .map(line => line.split('\t'))
    .filter(parts => parts.length === 2 && parts[0] && parts[1]);

  if (pairs.length === 0) process.exit(0);

  console.log(`Analyzing ${pairs.length} similar pair(s)...\n`);

  // Process in batches
  for (let i = 0; i < pairs.length; i += BATCH_SIZE) {
    const batch = pairs.slice(i, i + BATCH_SIZE);
    const results = await processBatch(batch);

    for (const result of results) {
      const match = result.match(/^MERGE:(.+?)\|(.+)$/);
      if (match) {
        mergeNotes(match[1].trim(), match[2].trim());
      }
    }
  }
}

main().catch(() => process.exit(0));
