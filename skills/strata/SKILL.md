---
name: strata
description: Alias de /stratavarious — exécute la consolidation complète de session et le handoff. Utiliser quand l'utilisateur invoque /strata, "save session", "fin de session", "consolide", ou veut persister les apprentissages de la conversation.
user-invocable: true
argument-hint: ""
allowed-tools: ["Bash", "Read", "Write", "Edit", "AskUserQuestion"]
---

Exécute le skill **stratavarious** dans son intégralité (8 phases : capture intentions → read → analyze → write → security scan → archive vault → git commit → cleanup).

Ce skill est un alias de `/stratavarious`. Toute la logique, les règles et les phases sont définies dans `skills/stratavarious/SKILL.md`.
