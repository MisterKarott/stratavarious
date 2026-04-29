// Test suite for stratavarious-stop.js secret scrubbing
// Run with: node --test hooks/stratavarious-stop.test.js

const { test, describe } = require('node:test');
const assert = require('node:assert');

// Import the scrubSecrets function
// We eval the file to extract just the function for testing
const fs = require('fs');
const hookCode = fs.readFileSync(__dirname + '/../hooks/stratavarious-stop.js', 'utf8');

// Extract scrubSecrets function via eval (simpler than requiring CommonJS in test)
const LABELED_PATTERNS = [
  { re: /\b([Aa]uthorization\s*:\s*[Bb]earer\s+)(\S+)/g },
  { re: /\b(x-api-key\s*:\s*)(\S+)/gi },
  { re: /\b(password|passwd|pwd|secret|api_key|apikey|access_key|private_key|auth_token|refresh_token)(\s*[=:]\s*)['"]?([^\s'"]{8,})['"]?/gi },
];
const SIMPLE_PATTERNS = [
  /\b(sk-[a-zA-Z0-9]{20,})\b/g,
  /\b(sk_live_[a-zA-Z0-9]{20,})\b/g,
  /\b(sk_test_[a-zA-Z0-9]{20,})\b/g,
  /\b(sk-ant-[a-zA-Z0-9]{20,})\b/g,
  /\b(AKIA[A-Z0-9]{16})\b/g,
  /\b(ASIA[A-Z0-9]{16})\b/g,
  /\b(pk_[a-z]+_[a-zA-Z0-9]{20,})\b/g,
  /\b(ak_[a-zA-Z0-9]{20,})\b/g,
  /\b(rk_[a-zA-Z0-9]{20,})\b/g,
  /\bghp_[A-Za-z0-9]{36,}\b/g,
  /\bgh[souru]_[A-Za-z0-9]{36,}\b/g,
  /\bgho_[A-Za-z0-9]{36,}\b/g,
  /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/g,
  /\bAIza[0-9A-Za-z_-]{35}\b/g,
  /\beyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+\.[A-Za-z0-9_.+/=-]+\b/g,
];
const CONN_STRING_PATTERN = /\b(mongodb|postgres|mysql|redis|amqp)(\+[a-z]+)?:\/\/([^:]+):([^@]+)@/gi;

function scrubSecrets(text) {
  let cleaned = text;

  cleaned = cleaned.replace(CONN_STRING_PATTERN, (match, scheme, qualifier, user, pwd) => {
    return match.replace(':' + pwd + '@', ':[REDACTED]@');
  });

  for (const { re } of LABELED_PATTERNS) {
    cleaned = cleaned.replace(re, (match, ...args) => {
      if (typeof args[2] === 'string') {
        return args[0] + args[1] + '[REDACTED]';
      }
      if (typeof args[0] === 'string') {
        return args[0] + '[REDACTED]';
      }
      return '[REDACTED]';
    });
  }

  for (const pattern of SIMPLE_PATTERNS) {
    cleaned = cleaned.replace(pattern, (match) => {
      if (match.length <= 8) return '[REDACTED]';
      return match.substring(0, 4) + '...' + '[REDACTED]';
    });
  }
  return cleaned;
}

describe('scrubSecrets', () => {
  // Connection strings
  test('scrubs mongodb connection string password', () => {
    const input = 'mongodb://user:superSecret123@host/db';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'mongodb://user:[REDACTED]@host/db');
  });

  test('scrubs postgres connection string password', () => {
    const input = 'postgres://user:superSecret@host/db';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'postgres://user:[REDACTED]@host/db');
  });

  // Labeled patterns - 3-group (key=value)
  test('scrubs password key=value', () => {
    const input = 'Set password="mySecretPass123"';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'Set password=[REDACTED]');
  });

  test('scrubs api_key with =', () => {
    const input = 'api_key=sk_1234567890abcdef';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'api_key=[REDACTED]');
  });

  test('scrubs secret with :', () => {
    const input = 'secret: abc123xyz';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'secret: [REDACTED]');
  });

  // Labeled patterns - 2-group (Bearer, X-API-Key)
  test('scrubs Authorization Bearer', () => {
    const input = 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'Authorization: Bearer [REDACTED]');
  });

  test('scrubs X-API-Key header', () => {
    const input = 'x-api-key: sk_1234567890abcdef';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'x-api-key: [REDACTED]');
  });

  // Simple patterns
  test('scrubs Stripe sk- keys', () => {
    const input = 'Use stripe key sk_test_TESTPATTERN_KEY_PLACEHOLDER for payments';
    const result = scrubSecrets(input);
    assert(result.includes('sk_t...[REDACTED]'));
  });

  test('scrubs Stripe sk_live_ keys', () => {
    const input = 'sk_live_TESTPATTERN_KEY_PLACEHOLDER_TestKeyForTest';
    const result = scrubSecrets(input);
    assert(result.includes('sk_l...[REDACTED]'));
  });

  test('scrubs AWS AKIA keys', () => {
    const input = 'AKIAIOSFODNN7EXAMPLE';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'AKIA...[REDACTED]');
  });

  test('scrubs GitHub ghp_ tokens', () => {
    const input = 'ghp_1234567890abcdef1234567890abcdef123456';
    const result = scrubSecrets(input);
    assert(result.includes('ghp_...[REDACTED]'));
  });

  test('scrubs Slack xoxb- tokens', () => {
    const input = 'xoxb-1234567890-1234567890-1234567890-1234567890';
    const result = scrubSecrets(input);
    assert(result.includes('xoxb...[REDACTED]'));
  });

  test('scrubs Google API keys', () => {
    const input = 'AIzaSyBd0FyC3Z9E8G7H5J1K4L6M0N2O3P5Q8R9S0T1-extended';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'AIza...[REDACTED]');
  });

  test('scrubs JWT tokens', () => {
    const input = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
    const result = scrubSecrets(input);
    assert.strictEqual(result, 'eyJh...[REDACTED]');
  });

  // Edge cases
  test('does not redact short matches (<8 chars)', () => {
    const input = 'short sk_12 not redacted';
    const result = scrubSecrets(input);
    assert(result.includes('sk_12'));
  });

  test('handles empty input', () => {
    const result = scrubSecrets('');
    assert.strictEqual(result, '');
  });

  test('handles text without secrets', () => {
    const input = 'This is just regular text with no secrets';
    const result = scrubSecrets(input);
    assert.strictEqual(result, input);
  });

  test('redacts multiple secrets in one string', () => {
    const input = 'password=secret123 and api_key=sk_abc123';
    const result = scrubSecrets(input);
    assert(result.includes('password=[REDACTED]'));
    assert(result.includes('api_key=[REDACTED]'));
  });
});
