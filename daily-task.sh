#!/bin/sh
# daily-task.sh — wrapper for Synology DSM Task Scheduler.
# Sets up PATH (DSM tasks run with a bare PATH), then runs the backup and
# appends output to a log next to the backups. Exits with the backup's
# status, so DSM's "terminates abnormally" email fires on failure.

# DSM Task Scheduler injects LD_PRELOAD=openhook.so, which Homebrew
# binaries can't load — every process would log a (harmless) warning.
unset LD_PRELOAD

# Homebrew is optional: its binaries need the root-owned /home symlink,
# which DSM updates delete. Load it only if it is actually usable.
BREW=/home/linuxbrew/.linuxbrew/bin/brew
if [ -x "$BREW" ]; then
  eval "$("$BREW" shellenv)"
fi

# A standalone (static) gh in ~/bin wins over Homebrew's; it needs no root
# and survives DSM updates. git falls back to the system /bin/git.
PATH="$HOME/bin:${PATH:-/usr/bin:/bin}"
export PATH

BACKUP_DIR="${BACKUP_DIR:-$HOME/Backup/GitHub}"
export BACKUP_DIR

LOG="$BACKUP_DIR/backup.log"
mkdir -p "$BACKUP_DIR"

"$(dirname "$0")/backup-github.sh" >>"$LOG" 2>&1
status=$?

# Keep the log from growing forever (last ~5000 lines).
tail -n 5000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"

if [ "$status" -ne 0 ]; then
  # Also print to stdout/stderr: DSM includes this in the failure email.
  echo "GitHub backup FAILED (exit $status) — last lines of $LOG:" >&2
  tail -n 20 "$LOG" >&2
fi
exit "$status"
