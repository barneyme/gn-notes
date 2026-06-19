# gn // get notes

Zero-dependency markdown notes synced to Koofr or GitHub.

`gn` is a simple Bash script that pulls a markdown note from cloud storage, opens it in your preferred editor, and pushes it back if anything changed.

No Git client. No database. No daemon. No Electron app.

Just:

- Markdown files
- `curl`
- A local folder
- Your editor

---

## Features

- Single-file Bash script
- Zero dependencies beyond common Unix tools
- Works with any editor through `$EDITOR`
- Syncs notes through:
  - Koofr (WebDAV)
  - GitHub repositories
- Automatic pull → edit → push workflow
- Search notes with grep
- List notes
- Rename notes
- Delete notes
- Sync all remote notes locally

---

## Requirements

The following tools must already be installed:

```bash
curl
grep
sed
awk
base64
tr
```

Most Linux, macOS, BSD, and WSL systems already include them.

---

## Installation

Download the script and place it somewhere on your PATH:

```bash
mv gn.sh ~/bin/gn
chmod +x ~/bin/gn
```

Run it:

```bash
gn
```

If no configuration exists, `gn` will walk you through setup.

---

# Setup

Choose one of the supported backends.

---

## Option A: Koofr

1. Create or sign in to your Koofr account.
2. Open:

   **Account Settings → Password**

3. Generate an App Password.
4. Use that password when configuring `gn`.

Do not use your normal account password.

Default WebDAV endpoint:

```text
https://app.koofr.net/dav/Koofr
```

---

## Option B: GitHub

### Create a Repository

Create a repository for your notes.

Example:

```text
gn
```

Private repositories work well.

### Create a Personal Access Token

Generate a GitHub Personal Access Token with:

```text
repo
```

permissions.

During setup you'll be asked for:

```text
GitHub username
Repository name
Personal Access Token
```

---

## Configuration Storage

Credentials are stored in:

```text
~/gn/gn.conf
```

Permissions are automatically set to:

```bash
chmod 600
```

Only your user account can read the file.

---

## First Run

Running `gn` without configuration starts the setup wizard:

```bash
$ gn

No config found at ~/gn/gn.conf - let's set one up.

Select your provider:
1) GitHub
2) Koofr
Choice [1-2]:
```

Example GitHub setup:

```text
Choice [1-2]: 1

GitHub Personal Access Token:
GitHub username (repo owner): your-username
Repository name: gn

Save this config for future runs? [Y/n]
```

---

# Usage

```bash
gn [options] [note]
```

---

## Open Default Note

```bash
gn
```

Opens:

```text
note.md
```

Creates it if it doesn't exist.

---

## Open a Note

```bash
gn ideas
```

Opens:

```text
ideas.md
```

Workflow:

```text
Pull remote copy
↓
Open editor
↓
Save changes
↓
Push back to remote
```

---

## Delete a Note

```bash
gn -d ideas
```

Deletes:

```text
ideas.md
```

Locally and remotely. Confirmation is required.

---

## Rename a Note

```bash
gn -r ideas projects
```

Renames:

```text
ideas.md → projects.md
```

Locally and remotely.

---

## Sync All Notes

```bash
gn -s
```

Downloads all remote notes into your local notes directory.

Useful when setting up a new machine.

---

## Reconfigure

```bash
gn -c
```

Deletes:

```text
~/gn/gn.conf
```

and starts setup again next time you run `gn`.

---

## Help

```bash
gn -h
```

Displays command help and local file commands.

---

# Local File Commands

Because notes are plain files in `~/gn/`, standard shell tools work on them directly:

```bash
ls -lt ~/gn/*.md                      # list notes, newest first
grep -ril "term" ~/gn/                # search notes (filenames only)
grep -rn "term" ~/gn/                 # search notes (with line numbers)
find ~/gn -name "*.md" -mtime -7      # notes modified in last 7 days
wc -l ~/gn/*.md | sort -rn            # largest notes by line count
cp -a ~/gn ~/gn-backup-$(date +%F)   # snapshot backup
```

---

# Notes Directory

By default notes are stored in:

```text
~/gn
```

Example:

```text
~/gn/
├── note.md
├── ideas.md
└── projects.md
```

---

# How Sync Works

When you open a note:

```text
1. Pull remote copy
2. Open editor
3. Detect changes via file hash
4. Push updated file
```

If nothing changed:

```text
No changes. Sync skipped.
```

---

# Conflict Handling

`gn` uses:

```text
Last write wins
```

There is:

- No merge engine
- No conflict detection
- No version resolution

If the same note is edited on two machines without syncing between them, the most recent upload replaces the older version. Run `gn -s` before starting a session on a new device.

---

# Editor Support

`gn` respects the standard:

```bash
$EDITOR
```

Examples:

```bash
export EDITOR=nano
export EDITOR=vim
export EDITOR=micro
export EDITOR=nvim
export EDITOR=hx
```

Default:

```text
nano
```

---

# Philosophy

`gn` follows a simple idea:

> Notes are just markdown files.

Your notes remain:

- Plain text
- Portable
- Searchable
- Future-proof

No proprietary database. No lock-in. No background sync service. Just files.

---

# License

MIT

---

# Author

Barney Matthews

```text
https://barney.me
```
