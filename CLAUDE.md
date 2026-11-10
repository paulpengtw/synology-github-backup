# CLAUDE.md

Shell scripts that back up every GitHub repo the authenticated `gh` user owns
(private + forks) onto a Synology NAS, run daily by DSM Task Scheduler.
Based on Myles Borins' article (see README); plain POSIX sh, no build system,
no dependencies beyond `git` and `gh`.

## Files

- `backup-github.sh` — the whole backup: lists repos via `gh repo list --json`
  (GraphQL, auto-paginated), clones new ones, fetch/pulls existing ones.
  Sources go to `$BACKUP_DIR/<username>/`, forks to `$BACKUP_DIR/forks/`.
- `daily-task.sh` — DSM Task Scheduler wrapper: unsets DSM's injected
  `LD_PRELOAD`, loads Homebrew's env only if usable, puts `~/bin` (static
  `gh`) first on PATH, logs to `$BACKUP_DIR/backup.log`, truncates the log
  to ~5000 lines.

Config is env vars only: `BACKUP_DIR` (default `$HOME/Backup/GitHub`) and
`LIMIT` (default 4000). No config files.

## Constraints that shaped the code

- **POSIX `/bin/sh`, not bash** — DSM's default shell runs these; keep
  constructs POSIX (no arrays, no `[[ ]]`).
- **DSM Task Scheduler runs with a bare env** — no PATH to Homebrew, plus an
  `LD_PRELOAD=openhook.so` injection that Homebrew binaries warn about.
  Everything env-related belongs in `daily-task.sh`, not `backup-github.sh`.
- **Homebrew is fragile on DSM** — its binaries need the root-owned
  `/home -> /volume1/homes` symlink, which DSM updates delete (broke the
  backup Sep–Nov 2026). Never make Homebrew a hard requirement; the static
  `gh` in `~/bin` + system `/bin/git` is the primary path.
- **No root** — a normal DSM user can't create shared folders or trigger
  scheduler tasks from the CLI; defaults must live under `$HOME`.
- **`git pull --ff-only` on purpose** — a force-pushed or diverged upstream
  must never rewrite backup state; the fetch (`git remote update -p`) still
  captures all refs.
- **Never prune** — repos deleted upstream stay on disk; that's the point of
  a backup.
- **Failures must exit non-zero** — DSM's "terminates abnormally" email is
  the only alerting. `backup-github.sh` lists repos up front (a failed list is
  an error, not zero repos), loops via here-docs so the `FAILED` counter
  survives, and treats a failed fetch as a failure (`git pull --ff-only`
  divergence is still ignored on purpose). `daily-task.sh` passes the status
  through after trimming the log. Don't print `failed`/`error` on success —
  the healthy-log grep below would match it.

## Testing changes

```sh
sh -n backup-github.sh daily-task.sh          # syntax check
BACKUP_DIR=~/.cache/bktest LIMIT=2 ./backup-github.sh  # quick run against a throwaway dir
env -i HOME=$HOME /bin/sh ./daily-task.sh      # simulate DSM's bare-env invocation
```

A healthy log run is a `=== GitHub backup` header, `Updating`/`Cloning` lines,
and a `=== Done` footer with nothing matching
`grep -iE 'error|fatal|failed' | grep -v openhook.so`.

## Docs

README.md is the user-facing contract (setup, scheduling, log reading,
troubleshooting). Behavior changes must update it in the same commit.
