# Vault sync across machines

StrataVarious is local-first by design. The vault lives at `$StrataVarious_HOME/memory/vault/` and is never synced automatically. This document explains how to sync it across multiple machines using a private git repository.

## Why git, not cloud sync

Cloud sync tools (Dropbox, Synology Drive, iCloud) work at the file level and have no awareness of concurrent writes. If two machines write to the vault simultaneously, you get conflicts or silent data loss. Git provides atomic commits, a full history, and an explicit merge step.

The vault is plain Markdown files — ideal for git. Diffs are human-readable. Conflicts are rare in practice (the vault is append-dominant).

## Setup (first machine)

```bash
cd "$StrataVarious_HOME/memory"

git init
cp /path/to/stratavarious/templates/vault.gitignore .gitignore

git add vault/ MEMORY.md profile.md StrataVarious.md
git commit -m "chore: initial vault snapshot"

git remote add origin git@github.com:yourname/my-vault-private.git
git push -u origin main
```

The repo **must** be private. Never push a public vault — it contains your project history and may contain sensitive context even after scrubbing.

## Setup (additional machines)

```bash
cd "$StrataVarious_HOME"
git clone git@github.com:yourname/my-vault-private.git memory
```

The vault is now live on the second machine. StrataVarious will write to it normally.

## What to commit

Commit:

- `vault/**/*.md` — durable knowledge entries
- `MEMORY.md` — rebuilt index
- `profile.md` — developer preferences
- `StrataVarious.md` — working memory

Do **not** commit:

- `session-buffer.md` — raw capture, machine-local, may contain unscrubbed data
- `.stratavarious-paused` — machine-local pause flag
- `.hook-errors.log` — machine-local error log
- `.vault.lock.d/` — transient lock directory
- `STRATA.md` at project roots — these are project-local handoffs

The `vault.gitignore` template covers all of the above.

## Daily workflow

After running `/stratavarious` on a machine:

```bash
cd "$StrataVarious_HOME/memory"
git add vault/ MEMORY.md profile.md StrataVarious.md
git commit -m "vault: $(date +%Y-%m-%d) consolidation"
git push
```

Before starting work on another machine:

```bash
cd "$StrataVarious_HOME/memory"
git pull --rebase
```

Using `--rebase` keeps the history linear and avoids noisy merge commits.

## Handling conflicts

Conflicts on vault notes are rare because each session writes new files (timestamped). Conflicts can occur on `MEMORY.md` and `StrataVarious.md`, which are rebuilt on every consolidation.

**MEMORY.md conflict.** Accept the incoming version (`git checkout --theirs MEMORY.md`) and re-run `scripts/stratavarious-memory-build.sh` to rebuild from the merged vault state. This is safe because MEMORY.md is generated from vault contents.

**StrataVarious.md conflict.** The file is a rolling window of the last 3 sessions. In a conflict, the safest resolution is to keep both machines' sessions and truncate to 3 sessions manually. The structure is plain Markdown — the sections are clearly delimited.

**vault note conflict.** Rare. If two machines write to the same vault file (same name, different content), resolve manually by keeping both entries in the file. Each entry is a self-contained Markdown section.

## What not to sync

Do not attempt to sync `session-buffer.md`. It is machine-local, updated dozens of times per session, and its raw content has not necessarily been through the full security scan yet. It is excluded by the `.gitignore` template.

## Remote recommendations

Use a **private** repository on any git host: GitHub, GitLab, Gitea self-hosted, or a bare repo on a NAS.

For NAS users (Synology, etc.), a bare git repo over SSH works well:

```bash
# On the NAS (SSH)
git init --bare /volume1/git/my-vault.git

# On each machine
git remote add origin synology-user@nas-hostname:/volume1/git/my-vault.git
```

Avoid relying on git LFS — vault files are small plain text.
