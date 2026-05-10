---
date: 2026-04-15
categorie: decision
tags: "#rate-limiting #api #infra"
projet: nemty
source_session: test-fixture
---

# Rate Limiting Strategy

We decided to implement token bucket rate limiting on the API gateway.
The rate limit is set to 100 requests per minute per user.
Rate limiting prevents abuse and ensures fair resource allocation.
We chose token bucket over sliding window because it handles burst traffic better.
