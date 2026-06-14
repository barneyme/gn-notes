# gn // get notes

Zero-dependency markdown notes synced to WebDAV, GitHub, or Dropbox.

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
  - WebDAV (Koofr, Nextcloud, ownCloud, etc.)
  - GitHub repositories
  - Dropbox
- Automatic pull → edit → push workflow
- Daily notes support
- Search notes with grep
- List notes
- Rename notes
- Delete notes
- Backup notes
- Sync all remote notes locally

---

## Requirements

The following tools must already be installed:

```bash
curl
grep
sed
awk
find
tar
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

## Option B: Generic WebDAV

Works with:

- Nextcloud
- ownCloud
- Synology
- Seafile
- Any WebDAV-compatible server

You'll need:

- WebDAV URL
- Username
- App password or access password
- Remote notes folder

Example:

```text
https://example.com/remote.php/dav/files/user/
```

---

## Option C: GitHub

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

Example:

```bash
gn
```

```text
GitHub Personal Access Token:
GitHub username: yourname
Repository name: gn
```

---

## Option D: Dropbox

### Create an App

Open the Dropbox Developer Console.

Create:

```text
Scoped Access
App Folder
```

application.

### Permissions

Enable:

```text
files.content.read
files.content.write
```

### Generate Refresh Token

Authorize:

```text
https://www.dropbox.com/oauth2/authorize?client_id=YOUR_APP_KEY&response_type=code&token_access_type=offline
```

Exchange the authorization code:

```bash
curl -s -X POST https://api.dropbox.com/oauth2/token \
  -d code=YOUR_AUTH_CODE \
  -d grant_type=authorization_code \
  -d client_id=YOUR_APP_KEY \
  -d client_secret=YOUR_APP_SECRET
```

Copy the returned:

```text
refresh_token
```

You'll enter it during setup.

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

1) Koofr (WebDAV)
2) Custom WebDAV Server
3) GitHub
4) Dropbox
```

Example GitHub setup:

```text
Choice [1-4]: 3

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

## Open Today's Note

```bash
gn -t
```

Creates or opens:

```text
YYYY-MM-DD.md
```

Example:

```text
2026-06-14.md
```

---

## List Notes

```bash
gn -l
```

Lists all local notes.

---

## Search Notes

```bash
gn -g meeting
```

Searches all local notes using grep.

---

## Delete a Note

```bash
gn -d ideas
```

Deletes:

```text
ideas.md
```

Locally and remotely.

Confirmation is required.

---

## Rename a Note

```bash
gn -r ideas projects
```

Renames:

```text
ideas.md
```

to:

```text
projects.md
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

## Create a Backup

```bash
gn -b
```

Creates:

```text
~/gn-YYYY-MM-DD.tar
```

containing all notes.

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

Displays command help.

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
├── projects.md
└── 2026-06-14.md
```

---

# How Sync Works

When you open a note:

```text
1. Pull remote copy
2. Open editor
3. Detect changes
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

If the same note is edited on two machines without syncing between them, the most recent upload replaces the older version.

---

# Editor Support

`gn` respects the standard:

```bash
$EDITOR
```

Examples:

```bash
export EDITOR=nano
```

```bash
export EDITOR=vim
```

```bash
export EDITOR=micro
```

```bash
export EDITOR=helix
```

```bash
export EDITOR=emacs
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

No proprietary database.

No lock-in.

No background sync service.

Just files.

---

# License

MIT

---

# Author

Barney Matthews

Website:

```text
https://barney.me
```
