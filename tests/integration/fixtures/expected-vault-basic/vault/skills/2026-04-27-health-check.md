---
date: 2026-04-27
categorie: skill
tags: #express #api #health-check
projet: node-project
source_session: ts-setup
---

# Express health check endpoint

Pattern for a simple health check endpoint at `/health` returning `{ status: 'ok', uptime: process.uptime() }`. Useful for Docker/Kubernetes readiness probes.
