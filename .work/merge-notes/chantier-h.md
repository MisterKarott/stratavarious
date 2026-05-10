# Chantier H — Merge Notes

**Branche :** `feat/strata-prune`
**Merge target :** `develop`
**Date :** 2026-05-10

## Livraisons

- `scripts/stratavarious-prune.sh` — vault hygiene (decay, trivial, duplicates)
- `skills/strata-prune/SKILL.md` — skill Claude Code user-invocable
- `tests/integration/test-prune.sh` — 27 tests (27/27)
- `tests/fixtures/prune-vault/` — vault de test avec 7 notes
- README : section "Vault hygiene" + entrées Commands/Scripts
- CHANGELOG : entrée Added

## Décisions de design

- **Levenshtein en awk** : implémenté en pur awk (DP classique), pas de dépendance externe, compatible Bash 3.2
- **Jaccard en awk** : tokenisation par split, ratio intersection/union > 0.7 → doublon
- **Cross-reference** : grep du stem (sans .md) dans le contenu des autres notes — simple et efficace
- **Dry-run par défaut** : `--apply` explicite requis pour modifier le vault
- **Confirmations** : `/dev/tty` pour ne pas interférer avec les pipes, fallback "no" si non-interactif
- **Doublons : pas d'auto-merge** : trop risqué, rapport seulement avec action "manual merge"
- **Réutilisation doctor** : `extract_fm_field` dupliqué (inline helper) pour éviter la dépendance — logique identique

## Bugs rencontrés et résolus

- **Fixtures trop courtes** : notes avec <5 lignes captées comme triviales → ajout de contenu
- **Titres peu similaires** : "Authentication Approach" vs "Authentication Method" → Jaccard 33%, Levenshtein > 3 → remplacé par "Rate Limit Configuration" vs "Rate Limits Configuration" (Levenshtein = 1)
- **Test 14 hang** : `--apply` sans `--yes` lit `/dev/tty` même avec stdin redirigé → remplacé par test `--apply --yes` sur copie temp
- **Sortie tronquée** : assertion `assert_not_contains` cherchait "auth-approach" dans toute la sortie, y compris la section duplicates → scope limité à la section Trivial

## Procédure de merge

```bash
cd stratavarious/
git checkout develop
git merge --no-ff feat/strata-prune -m "stratavarious: Chantier H — /strata-prune vault hygiene"
git branch -d feat/strata-prune
```
