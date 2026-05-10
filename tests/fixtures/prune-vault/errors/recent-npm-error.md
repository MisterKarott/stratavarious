---
date: 2026-04-25
categorie: error
tags: "#npm #node"
projet: "myproject"
source_session: test-fixture
---

# Recent NPM Error

NPM failed with EACCES permission denied on global install.
Root cause: npm global dir owned by root, not current user.
Fix: use nvm to manage Node versions — avoids sudo for npm globals.
Alternative: change npm global directory to user-writable path.
This error note is recent (within 60 days) — should NOT be a decay candidate.
Observed on macOS 14 with npm 10.x.
