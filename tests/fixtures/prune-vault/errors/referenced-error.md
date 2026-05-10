---
date: 2025-09-01
categorie: error
tags: "#cors #api"
projet: ""
source_session: test-fixture
---

# Referenced Error Note

CORS error when calling external API from browser.
Error: "Access to fetch at 'https://api.example.com' from origin has been blocked".
Fix: add proper Access-Control-Allow-Origin headers on the server side.
Also ensure preflight OPTIONS requests are handled correctly.
This old error is referenced by auth-approach.md and should NOT be a decay candidate.
Cross-origin credentials require explicit header configuration.
