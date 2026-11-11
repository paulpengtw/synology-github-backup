#!/bin/sh
# backup-github.sh — mirror all GitHub repos owned by the authenticated user
# onto local storage. Sources land in <BACKUP_DIR>/<username>/, forks in
# <BACKUP_DIR>/forks/. New repos are cloned; existing ones are fetched/pulled.
#
# Exits non-zero if the repo listing fails or any repo fails to clone/fetch,
# so a scheduler (e.g. DSM's "terminates abnormally" email) can alert on it.
#
# Requires: git + GitHub CLI (gh) on PATH, and `gh auth login` done once.
# Config (env vars, all optional):
#   BACKUP_DIR  where repos are stored   (default: $HOME/Backup/GitHub)
#   LIMIT       max repos per listing    (default: 4000)
set -u

BACKUP_DIR="${BACKUP_DIR:-$HOME/Backup/GitHub}"
LIMIT="${LIMIT:-4000}"

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found on PATH" >&2; exit 1; }
USERNAME="$(gh api user --jq .login)" || { echo "ERROR: gh is not authenticated (run: gh auth login)" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR" || exit 1

echo "=== GitHub backup for $USERNAME — $(date) ==="

clone_or_update() {
  repo="$1"   # owner/name on GitHub
  dest="$2"   # local path relative to BACKUP_DIR
  if [ -d "$dest/.git" ]; then
    echo "Updating $repo"
    (
      cd "$dest" || exit 1
      # Fetching origin is the actual backup — a failure here (auth, network)
      # must be reported, not swallowed; git's own message goes to the log.
      git fetch -q -p origin || exit 1
      # Other remotes are best-effort: `gh repo clone` gives forks an
      # `upstream` remote pointing at the parent repo, which may be deleted,
      # renamed or made private — that's not our data, so it must not fail
      # the backup.
      for remote in $(git remote); do
        [ "$remote" = origin ] && continue
        git fetch -q -p "$remote" >/dev/null 2>&1 || true
      done
      # Advance the default branch's working copy; other branches are kept
      # up to date as remote-tracking refs by the fetch above.
      # A diverged/force-pushed upstream is deliberately left alone (--ff-only).
      git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null || true
      git pull -q --ff-only 2>/dev/null || true
    )
  else
    echo "Cloning  $repo"
    gh repo clone "$repo" "$dest" -- -q
  fi
}

# List first, so a failed listing is an error rather than "zero repos".
SOURCES="$(gh repo list "$USERNAME" --source --limit "$LIMIT" --json nameWithOwner --jq '.[].nameWithOwner')" ||
  { echo "ERROR: could not list source repos"; exit 1; }
FORKS="$(gh repo list "$USERNAME" --fork --limit "$LIMIT" --json nameWithOwner --jq '.[].nameWithOwner')" ||
  { echo "ERROR: could not list forks"; exit 1; }

FAILED=0
# Here-docs (not pipes) keep the loops in this shell, so FAILED survives.
while read -r repo; do
  [ -n "$repo" ] || continue
  clone_or_update "$repo" "$repo" || { echo "ERROR: backup of $repo did not complete"; FAILED=$((FAILED + 1)); }
done <<EOF
$SOURCES
EOF

while read -r repo; do
  [ -n "$repo" ] || continue
  clone_or_update "$repo" "forks/${repo#*/}" || { echo "ERROR: backup of $repo did not complete"; FAILED=$((FAILED + 1)); }
done <<EOF
$FORKS
EOF

echo "=== Done — $(date) ==="
if [ "$FAILED" -gt 0 ]; then
  echo "ERROR: $FAILED repo(s) did not back up this run"
  exit 1
fi
