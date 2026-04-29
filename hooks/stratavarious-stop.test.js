// Unit tests for stratavarious-stop.js
// Run with: node --test

const assert = require('node:assert');

function testLabelPatterns() {
  const LABELED_PATTERNS = [
    { re: /\b([Aa]uthorization\s*:\s*[Bb]earer\s+)(\S+)/g },
    { re: /\b(x-api-key|Authorization\\s\*:\\s\*):\s\*)(\S\+)/gi },
    { re: /\b(password|passwd|pwd|secret|api_key|apikey|access_key|private_key|auth_token|refresh_token)(\s*[=:]\s*)['"]?([^\s'"]{8,})['"]?/gi },
  ];

  // Test 3-group patterns (key=value patterns should capture 3 groups)
  const tests = [
    { input: 'Authorization: Bearer token123', expectedGroups: 3, shouldMatch: true },
    { input: 'x-api-key: my-secret-key', expectedGroups: 2, shouldMatch: true },
    { input: 'Authorization: Bearer', expectedGroups: 3, shouldMatch: false }, // Only 2 groups
    { input: 'password=secret123', expectedGroups: 3, shouldMatch: false }, // Only 2 groups, but has separator
  ];

  for (const { input, expectedGroups, shouldMatch } of tests) {
    for (const { re } of LABELED_PATTERNS) {
      const match = input.match(re);
      if (!match) continue;

      // Count groups in match
      const groupCount = match.length - 1; // Exclude the full match (match[0])

      if (groupCount !== expectedGroups) {
        const gotGroups = groupCount;
        assert.strictEqual(gotGroups, expectedGroups,
          `FAIL: Pattern /${re.source}/ should capture ${expectedGroups} groups, got ${gotGroups} for input: "${input}"`);
      } else if (!shouldMatch) {
        assert.fail(`FAIL: Pattern /${re.source}/ matched when it shouldn't for input: "${input}"`);
      }
    }
  }

  console.log('✅ All label pattern tests passed');
}

function testSimplePatterns() {
  const SIMPLE_PATTERNS = [
    // Stripe
    /\b(sk-[a-zA-Z0-9]{17,})\b/g,
    // OpenAI
    /\b(sk-[a-zA-Z0-9]{20,})\b/g,
    // JWT
    /\beyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+\.[A-Za-z0-9_.+/=-]+\b/g,
  ];

  for (const pattern of SIMPLE_PATTERNS) {
      const tests = [
        { input: 'sk_live_TESTPATTERN_KEY_PLACEHOLDER', shouldMatch: true },
        { input: 'eyJhbGciOiJIzUzX0YzVy', shouldMatch: true },
        { input: 'sk_test_TESTPATTERN_KEY_PLACEHOLDER', shouldMatch: true },
      ];

      for (const { input, shouldMatch } of tests) {
        const match = input.match(pattern);
        if (!match) continue;

        const matches = pattern.test(input);
        assert.strictEqual(matches, shouldMatch,
          `FAIL: Pattern /${pattern.source}/ ${shouldMatch ? 'should' : 'should not'} match "${input}"`);
      }
    }

  console.log('✅ All simple pattern tests passed');
}

function testUnicodeStripping() {
  const tests = [
    { input: '​‏ ﻿­', expected: 'BFEFF' },
    { input: '­﻿﻿', expected: '00ADFEFF' },
    { input: '  ﻿­', expected: '00AD' },
  ];

  for (const { input, expected } of tests) {
    const result = input.replace(/​-‏- -﻿-­/g, '');
      assert.strictEqual(result, expected,
        `FAIL: Unicode stripping failed for "${input}" (expected: "${result}")`);
    }

  console.log('✅ All Unicode stripping tests passed');
}

// Run tests
testLabelPatterns();
testSimplePatterns();
testUnicodeStripping();
