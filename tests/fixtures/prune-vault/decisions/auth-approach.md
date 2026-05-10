---
date: 2026-03-15
categorie: decision
tags: "#auth #security"
projet: "myproject"
source_session: test-fixture
---

# Rate Limit Configuration

We chose token bucket algorithm for rate limiting the API.
Threshold: 100 requests per minute per user.
Implementation uses Redis sliding window counter.
Burst allowance of 20 requests before throttling kicks in.
References referenced-error for context on CORS with rate-limited endpoints.
Decision reviewed by security team on 2026-03-15.
