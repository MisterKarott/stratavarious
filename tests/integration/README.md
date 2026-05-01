# StrataVarious E2E Integration Tests

Tests end-to-end du plugin StrataVarious. Bash 3.2 compatible, sans framework externe.

## Structure

```
tests/integration/
├── fixtures/
│   ├── transcript-basic.jsonl          — Transcript simple sans secrets
│   ├── transcript-with-secrets.jsonl   — Transcript avec faux secrets variés
│   └── expected-vault-basic/           — Structure vault attendue après consolidation
├── test-e2e.sh                         — Script principal des tests
└── README.md                            — Ce fichier
```

## Exécuter les tests

Depuis la racine du repo :

```bash
# Tous les tests e2e
bash tests/integration/test-e2e.sh

# Test individuel (éditer le script pour appeler une fonction spécifique)
bash tests/integration/test-e2e.sh
```

Les tests créent un `STRATAVARIOUS_HOME` temporaire isolé via `mktemp -d` et le nettoient automatiquement.

## Ajouter un nouveau scénario

1. **Créer une fixture** dans `fixtures/` :
   - `transcript-<scenario>.jsonl` : Transcript JSONL d'entrée
   - `expected-vault-<scenario>/` : Structure vault attendue

2. **Ajouter une fonction de test** dans `test-e2e.sh` :
   ```bash
   test_<scenario>() {
       log_info "=== Test: <description> ==="
       # Setup: STRATAVARIOUS_TMP, vault, transcript
       # Action: Invoquer hook ou script
       # Assert: Vérifier résultats avec assert_*
       log_info "=== <scenario> test completed ==="
   }
   ```

3. **Ajouter au main** : Appeler `test_<scenario>` dans `main()`.

## Helpers d'assertion

- `assert_file_exists <path> <description>` : Vérifie qu'un fichier existe
- `assert_file_contains <path> <pattern> <description>` : Vérifie qu'un fichier contient un pattern
- `assert_file_not_contains <path> <pattern> <description>` : Vérifie l'absence d'un pattern

## Tests actuels

| Test | Description |
|------|-------------|
| `test_basic_capture` | Capture de session basique |
| `test_secret_scrubbing` | Scrubbing des secrets (Stripe, AWS, Anthropic, etc.) |
| `test_hook_invocation` | Invocation du Stop hook |
| `test_memory_build` | Reconstruction MEMORY.md |

## Contraintes

- Pas de framework externe (pas de bats, pas de shunit)
- Bash 3.2 compatible (macOS par défaut)
- Tests doivent tourner en moins de 30 secondes
- Nettoyage automatique en `trap EXIT`

## CI

Les tests e2e sont exécutés sur Ubuntu et macOS dans `.github/workflows/ci.yml`.
