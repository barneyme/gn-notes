# gn Installation & Usage Guide

`gn` (Get Notes) is a zero-dependency CLI note utility that saves markdown files directly to a private GitHub repository or a Dropbox app folder using native Bash and `curl`.

## Prerequisites

Before installing, set up credentials for **one** of the two supported backends:

* **GitHub**: A private repository named `gn` (the installer can create this for you), plus a Personal Access Token with full `repo` permissions.
* **Dropbox**: A scoped, app-folder Dropbox app with the `files.content.write` and `files.content.read` permissions, plus its App key, App secret, and a refresh token.

---

## Step-by-Step Installation

### Step 1: Create the Configuration File
Run the following commands to create the secure configuration directory and file:

mkdir -p ~/gn
nano ~/gn/gn.conf
chmod 600 ~/gn/gn.conf

Paste **one** of the following blocks into `gn.conf`, substituting your actual details, then save and exit. `gn` automatically detects which backend to use based on which variables are filled in.

**GitHub backend:**

GIT_TOKEN=your_personal_access_token_here
GIT_OWNER=your_username
GIT_REPO=gn

**Dropbox backend:**

DROPBOX_APP_KEY=your_app_key
DROPBOX_APP_SECRET=your_app_secret
DROPBOX_REFRESH_TOKEN=your_refresh_token
DROPBOX_PATH=/notes

### Step 2: Download and Install the Script

#### Option A: Automated One-liner (Recommended)
This script walks you through choosing GitHub or Dropbox, writes `gn.conf` for you, and downloads, permissions, and installs `gn` automatically:

curl -fsSL https://gn-notes.pages.dev/install.sh -o install.sh && chmod +x install.sh && ./install.sh

#### Option B: Manual Script Installation
If you downloaded `gn.sh` manually, make it executable and move it to your system path:

chmod +x gn.sh
sudo cp gn.sh /usr/local/bin/gn

---

## Help & Usage Guide

Once installed, use the following commands to manage your notes. Every command automatically syncs with your configured cloud remote (GitHub or Dropbox).

### Basic Usage
* `gn` — Opens your default `note.md` file.
* `gn daily-log` — Creates or opens `daily-log.md`.
* `gn work/reminders` — Creates a `work/` directory (if missing) and opens `reminders.md`.
* `gn -t` — Opens today's automated scratchpad entry (`YYYY-MM-DD.md`).

### Management & Search Commands
* `gn -h` — Displays the help page.
* `gn -l` — Lists all of your existing notes.
* `gn -g "todo"` — Finds and lists text matching "todo" inside any note.
* `gn -r old new` — Renames `old.md` to `new.md` both locally and on your cloud remote.
* `gn -d daily-log` — Deletes `daily-log.md` both locally and from your cloud remote.
