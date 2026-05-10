---
date: 2026-03-16
categorie: decision
tags: "#rate-limit #api"
projet: "myproject"
source_session: test-fixture
---

# Rate Limits Configuration

We chose token bucket algorithm for rate limiting the API.
Threshold: 100 requests per minute per user.
Implementation uses Redis sliding window counter.
Burst allowance of 20 requests before throttling kicks in.
This is a near-duplicate of auth-approach.md (Rate Limit Configuration).
Levenshtein distance between titles is 1 (added 's').

