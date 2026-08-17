#!/bin/sh
# backup-github.sh — mirror all GitHub repos owned by the authenticated user
# onto local storage. Sources land in <BACKUP_DIR>/<username>/, forks in
# <BACKUP_DIR>/forks/. New repos are cloned; existing ones are fetched/pulled.
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
      git remote update -p >/dev/null 2>&1
      # Advance the default branch's working copy; other branches are kept
      # up to date as remote-tracking refs by `git remote update` above.
      git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null || true
      git pull -q --ff-only 2>/dev/null || true
    )
  else
    echo "Cloning  $repo"
    gh repo clone "$repo" "$dest" -- -q
  fi
}

gh repo list "$USERNAME" --source --limit "$LIMIT" --json nameWithOwner --jq '.[].nameWithOwner' |
while read -r repo; do
  clone_or_update "$repo" "$repo"
done

gh repo list "$USERNAME" --fork --limit "$LIMIT" --json nameWithOwner --jq '.[].nameWithOwner' |
while read -r repo; do
  clone_or_update "$repo" "forks/${repo#*/}"
done

echo "=== Done — $(date) ==="
