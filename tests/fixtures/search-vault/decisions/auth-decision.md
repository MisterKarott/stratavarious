---
date: 2026-03-01
categorie: decision
tags: "#auth #security"
projet: nemty
source_session: test-fixture
---

# Authentication Decision

We chose JWT tokens over session cookies for the API.
JWT allows stateless authentication across multiple services.
The token expiry is set to 1 hour with a 7-day refresh window.
