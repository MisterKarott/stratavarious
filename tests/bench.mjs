#!/usr/bin/env node
// bench.mjs — Simple benchmark for Stop hook performance regression detection
// Run with: node tests/bench.mjs

import { performance } from 'node:perf_hooks';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Import hook functions dynamically
const hookPath = join(__dirname, '..', 'hooks', 'stratavarious-stop.js');
const { scrubSecrets, stripInvisibleUnicode, extractFromTranscript } = await import(hookPath);

function bench(name, fn, iterations = 1000) {
  const start = performance.now();
  for (let i = 0; i < iterations; i++) {
    fn();
  }
  const elapsed = performance.now() - start;
  const avgMs = elapsed / iterations;
  console.log(`✓ ${name}: ${(avgMs * 1000).toFixed(2)}μs avg (${iterations} iterations, ${elapsed.toFixed(0)}ms total)`);
  return avgMs;
}

// Generate synthetic transcript data (256 KB ~ typical Stop hook input)
function generateSyntheticTranscript() {
  const lines = [];
  const toolNames = ['write_file', 'edit', 'read_file', 'bash', 'grep'];
  const filePaths = ['/path/to/file.txt', '/another/file.md', '/config/settings.json'];

  for (let i = 0; i < 500; i++) {
    const toolName = toolNames[i % toolNames.length];
    const filePath = filePaths[i % filePaths.length];

    // User message
    lines.push(JSON.stringify({
      type: 'user',
      message: {
        content: `Please help me with task number ${i}. I need to process some data and generate a report.`
      }
    }));

    // Assistant tool use
    lines.push(JSON.stringify({
      type: 'assistant',
      message: {
        content: [
          {
            type: 'tool_use',
            name: toolName,
            input: toolName === 'bash' ? { command: `echo "Task ${i}"` } : { file_path: filePath }
          }
        ]
      }
    }));
  }

  return lines.join('\n');
}

// Generate synthetic text with secrets for scrubbing benchmark
function generateSecretText(size = 100000) {
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
console.log('Testing critical paths that execute after every Claude response...\n');

const results = {};

// Benchmark 1: scrubSecrets with 100KB text
console.log('1. scrubSecrets() - 100KB text with mixed patterns:');
const secretText = generateSecretText(100 * 1024);
results.scrubSecrets = bench('scrubSecrets', () => scrubSecrets(secretText), 100);
if (results.scrubSecrets > 5) {
  console.log(`  ⚠️  WARNING: scrubSecrets took ${results.scrubSecrets.toFixed(2)}ms (should be < 5ms)`);
}
console.log('');

// Benchmark 2: stripInvisibleUnicode with 100KB text
console.log('2. stripInvisibleUnicode() - 100KB text with Unicode:');
const unicodeText = 'Normal text with zero-width​spaces‌and﻿BOM­soft hyphens.'.repeat(1000);
results.stripInvisibleUnicode = bench('stripInvisibleUnicode', () => stripInvisibleUnicode(unicodeText), 100);
if (results.stripInvisibleUnicode > 2) {
  console.log(`  ⚠️  WARNING: stripInvisibleUnicode took ${results.stripInvisibleUnicode.toFixed(2)}ms (should be < 2ms)`);
}
console.log('');

// Benchmark 3: extractFromTranscript with 256 KB synthetic transcript
console.log('3. extractFromTranscript() - 256KB synthetic transcript:');
const transcriptLines = generateSyntheticTranscript().split('\n');
results.extractFromTranscript = bench('extractFromTranscript', () => extractFromTranscript(transcriptLines), 50);
if (results.extractFromTranscript > 20) {
  console.log(`  ⚠️  WARNING: extractFromTranscript took ${results.extractFromTranscript.toFixed(2)}ms (should be < 20ms)`);
}
console.log('');

// Overall assessment
console.log('📊 Performance Summary:');
const allPassed = Object.values(results).every((time, i) => {
  const thresholds = [5, 2, 20];
  return time < thresholds[i];
});

if (allPassed) {
  console.log('✅ All benchmarks passed - performance is within acceptable limits');
  process.exit(0);
} else {
  console.log('❌ Some benchmarks failed - performance regression detected');
  console.log('   Review changes before merging to avoid degrading user experience');
  process.exit(1);
}
