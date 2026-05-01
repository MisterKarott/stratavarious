---
date: 2026-04-27
categorie: pattern
tags: #git #docker #deployment #cicd
projet: node-project
source_session: ts-setup
---

# Pre-commit hook with lint-staged + Dockerfile

Pattern: use husky + lint-staged for pre-commit linting. Dockerfile uses node:20-alpine with `npm ci --production` for lean production images. Always add .dockerignore with node_modules and coverage.
