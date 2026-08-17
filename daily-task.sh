#!/bin/sh
# daily-task.sh — wrapper for Synology DSM Task Scheduler.
# Sets up the Homebrew environment (DSM tasks run with a bare PATH),
# then runs the backup and appends output to a log next to the backups.

# DSM Task Scheduler injects LD_PRELOAD=openhook.so, which Homebrew
# binaries can't load — every process would log a (harmless) warning.
unset LD_PRELOAD

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

BACKUP_DIR="${BACKUP_DIR:-$HOME/Backup/GitHub}"
export BACKUP_DIR

LOG="$BACKUP_DIR/backup.log"
mkdir -p "$BACKUP_DIR"

"$(dirname "$0")/backup-github.sh" >>"$LOG" 2>&1

# Keep the log from growing forever (last ~5000 lines).
tail -n 5000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
