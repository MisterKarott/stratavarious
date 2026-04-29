const { test, describe } = require('node:test');
const assert = require('node:assert');
const { scrubSecrets } = require('../hooks/stratavarious-stop.js');

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
});
