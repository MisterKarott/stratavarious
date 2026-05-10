---
date: 2026-04-10
categorie: pattern
tags: "#api #infra #retry"
projet: nemty
source_session: test-fixture
---

# API Retry Pattern

Use exponential backoff with jitter for API retry logic.
Start at 100ms, double each attempt, cap at 30s, add random jitter.
Rate limiting errors (429) should trigger the retry pattern.
This pattern avoids thundering herd problems during outages.
