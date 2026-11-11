# synology-github-backup

Automatically back up **all** of your GitHub repositories — private repos and
forks included — to a Synology NAS, refreshed daily by DSM Task Scheduler.

Based on Myles Borins' article
[Backing up GitHub with my Synology NAS](https://mylesborins.com/blog/backing-up-github-with-my-synology-nas/),
with a few fixes and improvements:

- Fixed the fork-path `sed` bug (the article's single-quoted `'s/$USERNAME/forks/'`
  never expands the variable).
- One script instead of four; the username is auto-detected from `gh auth`.
- Repo listing uses `gh --json`, which is robust against odd repo names, and the
  same `--limit` everywhere (the article cloned up to 4000 but only *updated* 1000).
- `git pull --ff-only` so a force-pushed upstream can never corrupt state, and a
  wrapper script that logs to a self-truncating log file.

## How it works

`gh repo list` (GraphQL, auto-paginated — not subject to the REST API's
100-per-page limit) enumerates every repo you own. Each repo is cloned on first
run and fetched/pulled on later runs:

```
Backup/GitHub/
├── <username>/      # your source repos (private ones included)
│   └── <repo>/
├── forks/           # your forks, kept separate
│   └── <repo>/
└── backup.log
```

Private repos work out of the box: `gh` lists them because you own them, and it
acts as a git credential helper, so clones and fetches over HTTPS authenticate
automatically. All branches are fetched as remote-tracking refs
(`git fetch -p origin`); the default branch is kept checked out so you can
browse files in File Station. Forks also get an `upstream` remote (the parent
repo) from `gh repo clone`; it is refreshed best-effort, so a parent that was
deleted, renamed or made private never fails the backup.

> **Not included:** issues, pull requests, wikis, and releases — this backs up
> the git data only. Deleted repos are intentionally never pruned locally.

## Prerequisites

- A Synology NAS with SSH enabled (DSM 7 tested).
- `git` — DSM 7 ships one at `/bin/git`.
- The GitHub CLI (`gh`). **Recommended:** the official static binary in
  `~/bin`, which needs no root and survives DSM updates (`daily-task.sh`
  puts `~/bin` first on PATH):

  ```sh
  V=2.103.3   # latest from https://github.com/cli/cli/releases
  curl -fsSLO https://github.com/cli/cli/releases/download/v$V/gh_${V}_linux_amd64.tar.gz
  tar xzf gh_${V}_linux_amd64.tar.gz
  mkdir -p ~/bin && cp gh_${V}_linux_amd64/bin/gh ~/bin/
  ```

  Homebrew's `gh` also works, but Homebrew on Synology depends on a
  root-owned `/home` symlink that DSM updates delete (see Troubleshooting).

## Setup

```sh
# 1. Get the scripts
git clone https://github.com/paulpengtw/synology-github-backup.git
cd synology-github-backup
chmod +x backup-github.sh daily-task.sh

# 2. Authenticate gh once (choose HTTPS; the token needs the default 'repo' scope),
#    and register it as git's credential helper for private repos
gh auth login
gh auth setup-git

# 3. First backup (defaults to ~/Backup/GitHub; override with BACKUP_DIR=...)
./backup-github.sh
```

## Schedule the daily run

In DSM: **Control Panel → Task Scheduler → Create → Scheduled Task → User-defined script**

- **General** — Task: `GitHub Backup`, User: *your user* (not root)
- **Schedule** — Daily, at a time you like (e.g. 03:00)
- **Task Settings** — Run command:

  ```sh
  /var/services/homes/YOURNAME/synology-github-backup/daily-task.sh
  ```

  **Recommended:** enable *"Send run details by email → only when the script
  terminates abnormally"*. The scripts exit non-zero if `gh` is missing, the
  token is invalid, the repo listing fails, or any repo fails to clone/fetch,
  and the email includes the last 20 log lines. Without it, a broken backup
  fails silently every night.

## Reading the log & verifying runs

Every run appends to `~/Backup/GitHub/backup.log` (auto-truncated to the last
~5000 lines by `daily-task.sh`). A run looks like:

```
=== GitHub backup for <username> — Mon Aug 17 15:17:12 CST 2026 ===
Updating paulpengtw/some-repo        # existing repo: fetched + pulled
Cloning  paulpengtw/new-repo         # repo created since the last run
=== Done — Mon Aug 17 15:24:03 CST 2026 ===
```

Useful checks:

```sh
# When did the last run finish?
grep '=== Done' ~/Backup/GitHub/backup.log | tail -1

# Watch a run live
tail -f ~/Backup/GitHub/backup.log

# How many repos did the latest run touch?
awk '/=== GitHub backup/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' \
  ~/Backup/GitHub/backup.log | grep -c '^Updating\|^Cloning'

# Any real errors? (excludes DSM's harmless LD_PRELOAD warning, see below)
grep -iE 'error|fatal|failed' ~/Backup/GitHub/backup.log | grep -v openhook.so
```

A healthy run has a matching `=== Done` line for every `=== GitHub backup`
header and nothing from the error grep. A repo that fails to clone or fetch gets
an `ERROR: backup of <repo> did not complete` line, preceded by git's own
`fatal:` message saying why (the rest of the run continues), and the run ends
with `ERROR: N repo(s) did not back up this run` and a non-zero exit. A header
without a `Done` means the run was interrupted; the next run picks up where it
left off, since every repo is independently cloned-or-updated.

## Troubleshooting

- **`ERROR: ld.so: object 'openhook.so' from LD_PRELOAD cannot be preloaded
  ... ignored.`** — DSM Task Scheduler injects `LD_PRELOAD=openhook.so` into
  tasks, which Homebrew binaries can't load. It is harmless and the run still
  succeeds; `daily-task.sh` unsets `LD_PRELOAD` so current versions don't log
  it at all.
- **`ERROR: gh not found on PATH` after a DSM update** — Homebrew on Synology
  lives under `/volume1/homes/linuxbrew`, but its binaries hardcode the loader
  path `/home/linuxbrew/.linuxbrew/lib/ld.so`, reached through a root-owned
  `/home -> /volume1/homes` symlink that DSM updates delete. Either install the
  static `gh` into `~/bin` (see Prerequisites) and re-run `gh auth setup-git`
  so git's credential helper points at it, or restore the symlink with a root
  **Triggered Task → Boot-up** running
  `[ -e /home ] || ln -s /volume1/homes /home`.
- **Runs suddenly fail with authentication errors** — your GitHub token
  expired or was revoked. SSH in and run `gh auth login` again. This is why
  enabling the Task Scheduler abnormal-termination email matters.
- **A repo keeps reporting nothing / stale default branch** — its default
  branch is named something other than `main`/`master`. All branches are still
  fetched as remote-tracking refs (nothing is lost); only the checked-out
  working copy stays behind. `cd` into it and `git checkout <branch>` once.
- **Testing outside the scheduler** — run `./daily-task.sh` manually over SSH;
  it behaves identically and writes to the same log.

## Configuration

Both scripts accept environment variables:

| Variable     | Default              | Meaning                          |
|--------------|----------------------|----------------------------------|
| `BACKUP_DIR` | `$HOME/Backup/GitHub`| Where repos are stored           |
| `LIMIT`      | `4000`               | Max repos per listing            |

## Backing up organization repos

`gh repo list <you>` only covers repos **you own**. For an org, add extra loops
or simply run with the org name, e.g.:

```sh
gh repo list MY-ORG --limit 4000 --json nameWithOwner --jq '.[].nameWithOwner' |
while read -r repo; do
  gh repo clone "$repo" "$repo" -- -q 2>/dev/null || git -C "$repo" remote update -p
done
```

## License

MIT
