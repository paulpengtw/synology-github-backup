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
(`git remote update -p`); the default branch is kept checked out so you can
browse files in File Station.

> **Not included:** issues, pull requests, wikis, and releases — this backs up
> the git data only. Deleted repos are intentionally never pruned locally.

## Prerequisites

- A Synology NAS with SSH enabled (DSM 7 tested).
- `git` and the GitHub CLI (`gh`). The easiest route is
  [Homebrew on Synology](https://github.com/zebernst/synology-homebrew) (or any
  Synology Homebrew installer), then:

  ```sh
  brew install gh
  ```

## Setup

```sh
# 1. Get the scripts
git clone https://github.com/paulpengtw/synology-github-backup.git
cd synology-github-backup
chmod +x backup-github.sh daily-task.sh

# 2. Authenticate gh once (choose HTTPS; the token needs the default 'repo' scope)
gh auth login

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

  Optionally enable *"Send run details by email → only when the script
  terminates abnormally"* so you notice if a token expires.

Output lands in `~/Backup/GitHub/backup.log`.

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
