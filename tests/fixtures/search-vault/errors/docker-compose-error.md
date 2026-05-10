---
date: 2026-04-20
categorie: error
tags: "#docker #infra"
projet: ""
source_session: test-fixture
---

# Docker Compose Volume Error

Docker compose failed with a volume mount error when running on macOS.
The error was: "Mounts denied: The path /var/lib/docker is not shared".
Fix: add the path to Docker Desktop shared paths in preferences.
This is a global infrastructure note, not project-specific.
