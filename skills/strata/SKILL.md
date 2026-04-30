---
name: strata
description: Alias de /stratavarious — exécute la consolidation complète de session, produit STRATA.md (handoff portable à la racine du projet) et archive dans le vault. Utiliser quand l'utilisateur invoque /strata, "save session", "fin de session", "consolide", ou veut persister les apprentissages de la conversation.
user-invocable: true
argument-hint: ""
allowed-tools: ["Bash", "Read", "Write", "Edit", "AskUserQuestion"]
---

Exécute le skill **stratavarious** dans son intégralité (8 phases : capture intentions → read → analyze → write STRATA.md → write STRATAVARIOUS.md → security scan → archive vault → cleanup).

Ce skill est un alias de `/stratavarious`. Toute la logique, les règles et les phases sont définies dans `skills/stratavarious/SKILL.md`.
