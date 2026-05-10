const { test, describe } = require('node:test');
const assert = require('node:assert');
const { scrubSecrets, stripInvisibleUnicode, extractFromTranscript, shannonEntropy } = require('../hooks/stratavarious-stop.js');

describe('scrubSecrets', () => {
  test('mongodb password redacted', () => {
    assert.strictEqual(
      scrubSecrets('mongodb://user:superSecret123@host/db'),
      'mongodb://user:[REDACTED]@host/db'
    );
  });

  test('Authorization Bearer redacted', () => {
    assert.strictEqual(
      scrubSecrets('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9'),
      'Authorization: Bearer [REDACTED]'
    );
  });

  test('Authorization Basic redacted', () => {
    assert.strictEqual(
      scrubSecrets('Authorization: Basic dXNlcm5hbWU6cGFzc3dvcmQ='),
      'Authorization: Basic [REDACTED]'
    );
  });

  test('HTTP basic auth in URL redacted', () => {
    assert.strictEqual(
      scrubSecrets('https://user:password@api.example.com/endpoint'),
      'https://user:[REDACTED]@api.example.com/endpoint'
    );
  });

  test('x-api-key header redacted', () => {
    assert.strictEqual(
      scrubSecrets('x-api-key: sk_1234567890abcdef'),
      'x-api-key: [REDACTED]'
    );
  });

  test('password=value redacted', () => {
    assert.strictEqual(
      scrubSecrets('password="mySecretPass123"'),
      'password=[REDACTED]'
    );
  });

  test('AWS AKIA key redacted', () => {
    assert.strictEqual(
      scrubSecrets('AKIAIOSFODNN7EXAMPLE'),
      'AKIA...[REDACTED]'
    );
  });

  test('plain text untouched', () => {
    const txt = 'Just a sentence with no secrets.';
    assert.strictEqual(scrubSecrets(txt), txt);
  });

  test('empty string', () => {
    assert.strictEqual(scrubSecrets(''), '');
  });

  // Negative test: "the secret to happiness is..." should NOT be redacted (benign phrase)
  test('benign phrase with "secret" not redacted', () => {
    const txt = 'The secret to happiness is living in the moment.';
    assert.strictEqual(scrubSecrets(txt), txt);
  });

  // Test that secret patterns require proper context (line start or YAML)
  test('secret pattern requires line start or YAML context', () => {
    // This should NOT match because it's mid-sentence without = or :
    const txt = 'I discovered a secret garden behind the house';
    assert.strictEqual(scrubSecrets(txt), txt);
  });
});

describe('stripInvisibleUnicode', () => {
  test('removes zero-width spaces', () => {
    const txt = 'Hello​World';
    assert.strictEqual(stripInvisibleUnicode(txt), 'HelloWorld');
  });

  test('removes zero-width non-joiner', () => {
    const txt = 'co‌operation';
    assert.strictEqual(stripInvisibleUnicode(txt), 'cooperation');
  });

  test('removes soft hyphen', () => {
    const txt = 'fac­tory';
    assert.strictEqual(stripInvisibleUnicode(txt), 'factory');
  });

  test('removes BOM', () => {
    const txt = '﻿Hello';
    assert.strictEqual(stripInvisibleUnicode(txt), 'Hello');
  });

  test('removes TAG characters (U+E0000-U+E007F)', () => {
    const txt = 'Normal󠀀Text';
    assert.strictEqual(stripInvisibleUnicode(txt), 'NormalText');
  });

  test('preserves normal text', () => {
    const txt = 'Normal text with émojis 🎉 and spëcial çharacters';
    assert.strictEqual(stripInvisibleUnicode(txt), txt);
  });
});

describe('extractFromTranscript', () => {
  test('extracts user messages from JSONL', () => {
    const lines = [
      '{"type":"user","message":{"content":"Hello, how are you?"}}',
      '{"type":"assistant","message":{"content":[null]}}',
    ];
    const result = extractFromTranscript(lines);
    assert.strictEqual(result.userMessages.length, 1);
    assert.strictEqual(result.userMessages[0], 'Hello, how are you?');
  });

  test('extracts tool calls from JSONL', () => {
    const lines = [
      '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"write_file","input":{"file_path":"/path/to/file.txt"}}]}}',
    ];
    const result = extractFromTranscript(lines);
    assert.strictEqual(result.toolCalls.length, 1);
    assert.strictEqual(result.toolCalls[0].name, 'write_file');
    assert.strictEqual(result.toolCalls[0].path, '/path/to/file.txt');
  });

  test('detects errors in tool results', () => {
    const lines = [
      '{"type":"user","message":{"content":[{"type":"tool_result","content":"Error: Command failed","is_error":true}]}}',
    ];
    const result = extractFromTranscript(lines);
    assert.strictEqual(result.errors.length, 1);
    assert.strictEqual(result.errors[0], 'Error: Command failed');
  });

  test('limits results to last N entries', () => {
    // Create more than the limits
    const lines = [];
    for (let i = 0; i < 10; i++) {
      lines.push(`{"type":"user","message":{"content":"Message ${i}"}}`);
    }
    const result = extractFromTranscript(lines);
    assert.strictEqual(result.userMessages.length, 3); // Limited to last 3
    assert.strictEqual(result.userMessages[2], 'Message 9');
  });

  test('handles malformed JSON lines gracefully', () => {
    const lines = [
      '{"type":"user","message":{"content":"Valid message"}}',
      'invalid json line',
      '{"type":"assistant","message":{"content":[null]}}',
    ];
    const result = extractFromTranscript(lines);
    assert.strictEqual(result.userMessages.length, 1);
  });
});

// --- Chantier C: nouveaux patterns ---

describe('scrubSecrets: Anthropic sk-ant-', () => {
  test('redacts Anthropic API key (positive)', () => {
    const key = 'sk-ant-api03-aBcDeFgHiJkLmNoPqRsTuVwXyZ01234567890abcdef';
    const result = scrubSecrets(`token=${key}`);
    assert.ok(!result.includes(key), `Expected key to be redacted, got: ${result}`);
  });

  test('preserves short sk-ant- that is not a real key (negative)', () => {
    // Only 5 chars after prefix — below 20 char threshold
    const txt = 'sk-ant-short';
    assert.strictEqual(scrubSecrets(txt), txt);
  });
});

describe('scrubSecrets: GitHub fine-grained PAT', () => {
  test('redacts github_pat_ token (positive)', () => {
    const pat = 'github_pat_11AAAAAAAA0XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
    const result = scrubSecrets(`my token: ${pat}`);
    assert.ok(!result.includes(pat), `Expected PAT to be redacted, got: ${result}`);
    assert.ok(result.includes('[REDACTED]'), `Expected [REDACTED] in result`);
  });

  test('does not redact github_pat_ with short suffix (negative)', () => {
    const txt = 'github_pat_short';
    assert.strictEqual(scrubSecrets(txt), txt);
  });
});

describe('scrubSecrets: Google OAuth ya29.', () => {
  test('redacts Google OAuth access token (positive)', () => {
    const token = 'ya29.A0AfH6SMABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const result = scrubSecrets(`Authorization: Bearer ${token}`);
    assert.ok(!result.includes(token), `Expected OAuth token to be redacted, got: ${result}`);
  });

  test('does not redact ya29. with short suffix (negative)', () => {
    const txt = 'ya29.short';
    assert.strictEqual(scrubSecrets(txt), txt);
  });
});

describe('scrubSecrets: strict mode', () => {
  test('strict mode redacts mid-line api_key= (positive)', () => {
    const txt = 'config: api_key=MySecretKey123456';
    const result = scrubSecrets(txt, { strict: true });
    assert.ok(!result.includes('MySecretKey123456'), `Expected key redacted, got: ${result}`);
  });

  test('default mode does NOT redact mid-line api_key= (negative)', () => {
    // Default (non-strict) requires line start — mid-line should NOT be redacted
    const txt = 'inline config: api_key=MySecretKey123456';
    const result = scrubSecrets(txt);
    assert.strictEqual(result, txt, `Default mode should not redact mid-line match`);
  });
});

describe('shannonEntropy', () => {
  test('high-entropy string (base64-like key)', () => {
    // Random-looking key: entropy should be > 4.5
    const key = 'aB3kLmN9pQrSt7uVwXyZ012345';
    const h = shannonEntropy(key);
    assert.ok(h > 4.0, `Expected entropy > 4.0, got ${h}`);
  });

  test('low-entropy string (repetitive)', () => {
    // Repetitive string: entropy should be low
    const h = shannonEntropy('aaaaaaaaaaaaaaaaaaaaaa');
    assert.strictEqual(h, 0, `Expected entropy 0 for all-same string, got ${h}`);
  });

  test('empty string returns 0', () => {
    assert.strictEqual(shannonEntropy(''), 0);
  });
});

describe('scrubSecrets: entropy scan', () => {
  test('entropy mode redacts high-entropy long string (positive)', () => {
    // Realistic high-entropy token (>20 chars, entropy >4.5)
    const token = 'xK9mP2qR5sT8vW1yA4bC7dE0fG3hI6jL';
    const result = scrubSecrets(token, { entropy: true });
    assert.ok(result.includes('[REDACTED-ENTROPY]'), `Expected entropy redaction, got: ${result}`);
  });

  test('entropy mode does not redact short string (negative)', () => {
    // Short — below 20 char threshold
    const txt = 'shorttoken123';
    const result = scrubSecrets(txt, { entropy: true });
    assert.strictEqual(result, txt);
  });

  test('entropy mode does not redact low-entropy repeated pattern (negative)', () => {
    // Repetitive: aaaaaaaaaaaaaaaaaaaaa — entropy ~= 0
    const txt = 'aaaaaaaaaaaaaaaaaaaaa';
    const result = scrubSecrets(txt, { entropy: true });
    assert.strictEqual(result, txt);
  });

  test('entropy mode off by default (negative)', () => {
    const token = 'xK9mP2qR5sT8vW1yA4bC7dE0fG3hI6jL';
    const result = scrubSecrets(token);
    assert.ok(!result.includes('[REDACTED-ENTROPY]'), 'Entropy mode should be off by default');
  });
});

// Simple benchmark for performance regression detection
describe('performance: scrubSecrets', () => {
  test('scrubs 100KB of text in under 10ms', () => {
    // Generate 100KB of text with various patterns
    const chunks = [];
    for (let i = 0; i < 1000; i++) {
      chunks.push('Normal text with some patterns: ');
      chunks.push('password=secret123 ');
      chunks.push('Authorization: Bearer token ');
      chunks.push('https://user:pass@host.com ');
      chunks.push('Just a sentence describing the secret to success. ');
    }
    const largeText = chunks.join('\n');

    const start = Date.now();
    scrubSecrets(largeText);
    const elapsed = Date.now() - start;

    assert.ok(elapsed < 10, `scrubSecrets took ${elapsed}ms, expected < 10ms`);
  });
});
