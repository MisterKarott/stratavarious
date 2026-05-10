#!/usr/bin/env node
// bench.mjs — Performance benchmark for Stop hook regression detection
// Run with: node tests/bench.mjs

import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const hookPath = join(__dirname, '..', 'hooks', 'stratavarious-stop.js');
const { scrubSecrets, stripInvisibleUnicode, extractFromTranscript } = await import(hookPath);

// Returns { avg, p50, p95, max } in ms
function bench(name, fn, iterations = 1000) {
  const times = [];
  for (let i = 0; i < iterations; i++) {
    const t0 = performance.now();
    fn();
    times.push(performance.now() - t0);
  }
  times.sort((a, b) => a - b);
  const total = times.reduce((s, t) => s + t, 0);
  const avg = total / iterations;
  const p50 = times[Math.floor(iterations * 0.5)];
  const p95 = times[Math.floor(iterations * 0.95)];
  const max = times[iterations - 1];
  console.log(
    `  ✓ ${name}: avg=${avg.toFixed(2)}ms  P50=${p50.toFixed(2)}ms  P95=${p95.toFixed(2)}ms  max=${max.toFixed(2)}ms  (${iterations} iter)`
  );
  return { avg, p50, p95, max };
}

// Synthetic transcript: `entries` JSONL lines, realistic tool mix
function generateSyntheticTranscript(entries = 500) {
  const lines = [];
  const toolNames = ['write_file', 'edit', 'read_file', 'bash', 'grep'];
  const filePaths = ['/path/to/file.txt', '/another/file.md', '/config/settings.json'];

  for (let i = 0; i < entries; i++) {
    const toolName = toolNames[i % toolNames.length];
    const filePath = filePaths[i % filePaths.length];

    lines.push(JSON.stringify({
      type: 'user',
      message: { content: `Please help me with task number ${i}. I need to process some data and generate a report.` }
    }));

    lines.push(JSON.stringify({
      type: 'assistant',
      message: {
        content: [{
          type: 'tool_use',
          name: toolName,
          input: toolName === 'bash' ? { command: `echo "Task ${i}"` } : { file_path: filePath }
        }]
      }
    }));
  }

  return lines.join('\n');
}

// 256 KiB text with ~20 secrets evenly distributed (realistic density)
function generateRealisticSecretText(size = 256 * 1024, secretCount = 20) {
  const secretPatterns = [
    'password=superSecret123',
    'Authorization: Bearer sk_test_1234567890abcdef',
    'mongodb://user:secretPass@host/db',
    'AKIAIOSFODNN7EXAMPLE',
    'sk-proj-abcdefghijklmnopqrstuvwxyz123456'
  ];

  const filler = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris. ';
  const secretLen = secretPatterns.reduce((s, p) => s + p.length, 0) / secretPatterns.length;
  const segmentSize = Math.floor((size - secretCount * secretLen) / (secretCount + 1));

  const chunks = [];
  for (let i = 0; i <= secretCount; i++) {
    let seg = '';
    while (seg.length < segmentSize) seg += filler;
    chunks.push(seg.substring(0, segmentSize));
    if (i < secretCount) {
      chunks.push(secretPatterns[i % secretPatterns.length]);
    }
  }

  return chunks.join('\n').substring(0, size);
}

// 100 KB text with high-density secrets (regression guard for existing threshold)
function generateHighDensitySecretText(size = 100 * 1024) {
  const chunks = [];
  const secretPatterns = [
    'password=superSecret123',
    'Authorization: Bearer sk_test_1234567890abcdef',
    'mongodb://user:secretPass@host/db',
    'AKIAIOSFODNN7EXAMPLE',
    'sk-proj-abcdefghijklmnopqrstuvwxyz123456'
  ];
  for (let i = 0; i < size / 100; i++) {
    chunks.push('Normal text describing the secret to happiness and success. ');
    chunks.push(secretPatterns[i % secretPatterns.length]);
    chunks.push('More normal text without secrets. ');
  }
  return chunks.join('\n').substring(0, size);
}

console.log('🚀 StrataVarious Stop Hook Performance Benchmark\n');
console.log('Node', process.version, '— testing critical paths that run after every Claude response\n');

const results = {};
let allPassed = true;

// 1. scrubSecrets — 100 KB high-density (regression guard)
console.log('1. scrubSecrets() — 100 KB, high-density secrets:');
const highDensityText = generateHighDensitySecretText(100 * 1024);
results.scrubSecretsHighDensity = bench('scrubSecrets (100KB dense)', () => scrubSecrets(highDensityText), 100);
if (results.scrubSecretsHighDensity.p95 > 5) {
  console.log(`  ⚠️  P95 ${results.scrubSecretsHighDensity.p95.toFixed(2)}ms > 5ms threshold`);
  allPassed = false;
}
console.log('');

// 2. scrubSecrets — 256 KB, ~20 realistic secrets (production-realistic)
console.log('2. scrubSecrets() — 256 KB, ~20 secrets (realistic density):');
const realisticSecretText = generateRealisticSecretText(256 * 1024, 20);
results.scrubSecretsRealistic = bench('scrubSecrets (256KB realistic)', () => scrubSecrets(realisticSecretText), 100);
if (results.scrubSecretsRealistic.p95 > 20) {
  console.log(`  ⚠️  P95 ${results.scrubSecretsRealistic.p95.toFixed(2)}ms > 20ms threshold`);
  allPassed = false;
}
console.log('');

// 3. stripInvisibleUnicode — 100 KB
console.log('3. stripInvisibleUnicode() — 100 KB:');
const unicodeText = 'Normal text with zero-width​spaces‌and﻿BOM­soft hyphens.'.repeat(1000);
results.stripInvisibleUnicode = bench('stripInvisibleUnicode (100KB)', () => stripInvisibleUnicode(unicodeText), 100);
if (results.stripInvisibleUnicode.p95 > 2) {
  console.log(`  ⚠️  P95 ${results.stripInvisibleUnicode.p95.toFixed(2)}ms > 2ms threshold`);
  allPassed = false;
}
console.log('');

// 4. extractFromTranscript — 500 entries (baseline)
console.log('4. extractFromTranscript() — 500 entries (baseline):');
const transcriptSmall = generateSyntheticTranscript(500).split('\n');
results.extractBaseline = bench('extractFromTranscript (500 entries)', () => extractFromTranscript(transcriptSmall), 50);
if (results.extractBaseline.p95 > 20) {
  console.log(`  ⚠️  P95 ${results.extractBaseline.p95.toFixed(2)}ms > 20ms threshold`);
  allPassed = false;
}
console.log('');

// 5. extractFromTranscript — 1000 entries, 256 KiB (production-realistic)
console.log('5. extractFromTranscript() — 1000 entries, ~256 KiB (realistic):');
const transcriptLarge = generateSyntheticTranscript(1000).split('\n');
results.extractLarge = bench('extractFromTranscript (1000 entries)', () => extractFromTranscript(transcriptLarge), 100);
if (results.extractLarge.p95 > 500) {
  console.log(`  ⚠️  P95 ${results.extractLarge.p95.toFixed(2)}ms > 500ms threshold (hook timeout risk)`);
  allPassed = false;
}
console.log('');

// Summary
console.log('📊 Performance Summary:');
console.log('');
console.log('  Benchmark                         │ P50 (ms) │ P95 (ms) │ Threshold │ Status');
console.log('  ──────────────────────────────────┼──────────┼──────────┼───────────┼───────');

const rows = [
  ['scrubSecrets (100KB dense)',         results.scrubSecretsHighDensity, 5],
  ['scrubSecrets (256KB realistic)',      results.scrubSecretsRealistic,   20],
  ['stripInvisibleUnicode (100KB)',       results.stripInvisibleUnicode,   2],
  ['extractFromTranscript (500 entries)', results.extractBaseline,         20],
  ['extractFromTranscript (1000 entries)',results.extractLarge,            500],
];

for (const [label, r, threshold] of rows) {
  const pass = r.p95 <= threshold;
  const status = pass ? '✅ pass' : '❌ FAIL';
  const p50  = r.p50.toFixed(2).padStart(8);
  const p95  = r.p95.toFixed(2).padStart(8);
  const thr  = String(threshold + 'ms').padStart(9);
  console.log(`  ${label.padEnd(34)}│ ${p50} │ ${p95} │ ${thr} │ ${status}`);
}

console.log('');
if (allPassed) {
  console.log('✅ All benchmarks within thresholds');
  process.exit(0);
} else {
  console.log('❌ Performance regression detected — review before merging');
  process.exit(1);
}
