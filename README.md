# gn

**get_notes.md**

`gn` (Get Notes) is a zero-dependency CLI note utility that saves your markdown files directly to a private GitHub, GitLab, Codeberg or Bitbucket repository. It acts as a lightweight sync layer using nothing but native Bash and curl - no local Git installation or setup required.

When you run `gn note-name`, it pulls the latest file version from your Git host via HTTP API, opens it in your default `$EDITOR`, and automatically pushes your changes back when you save and exit.

It runs completely in the foreground with zero background daemons, no local databases, and no tracking.

---

## Prerequisites & Provider Configuration

`gn` requires a private remote repository and a personal access token generated from your chosen host provider.

### 0. Git Cloud Workspace Account

Create an account with GitHub, GitLab, or Codeberg.

### A. GitHub Configuration

Create a private repository named `gn` and generate a token with full `repo` permissions.

- GitHub PAT Token Docs
- Direct Token Generation Link

### B. GitLab Configuration

Create a private project named `gn` and generate a Personal Access Token with the `api` scope.

### C. Codeberg Configuration

Create a private repository named `gn` and generate a token with repository access permissions.


### D. Bitbucket Configuration

Create a private repository named gn. Bitbucket uses App Passwords rather than personal access tokens - generate one under your account settings with Repositories: Read and Write permissions checked. Use your Bitbucket username as GIT_OWNER and the App Password as GIT_TOKEN.

---

## Download gn

### Option A: One-liner (Recommended)

```bash
curl -fsSL https://gn-notes.pages.dev/install.sh -o install.sh && chmod +x install.sh && ./install.sh
```

### Option B: Manual Setup

Download:

- `gn.sh`
- `gn.conf`

---

## Manual Installation

### 1. Create the Config File

```bash
mkdir -p ~/gn
nano ~/gn/gn.conf
chmod 600 ~/gn/gn.conf
```

```bash
GIT_PROVIDER=github
GIT_TOKEN=your_personal_access_token_here
GIT_OWNER=your_username
GIT_REPO=gn
```

### 2. Make the Script Available Globally

```bash
chmod +x gn.sh
sudo cp gn.sh /usr/local/bin/gn
```

### 3. Using gn

```bash
gn                  # Opens your main index.md
gn daily-log        # Creates/Opens daily-log.md
gn work/reminders   # Creates work/ directory and opens reminders.md
gn -h               # Displays help page
gn -l               # Lists all your notes
gn -g "todo"        # Finds text matching "todo" inside any note
gn -t               # Opens today's automated scratchpad entry
gn -d daily-log     # Deletes daily-log.md locally and from cloud remote
gn -r old new       # Renames old.md to new.md locally and on cloud remote
```

---

## Setting Up a Second Computer

### 1. Create the notes directory and config file

```bash
mkdir -p ~/gn
nano ~/gn/gn.conf
chmod 600 ~/gn/gn.conf
```

```bash
GIT_PROVIDER=github
GIT_TOKEN=your_personal_access_token_here
GIT_OWNER=your_username
GIT_REPO=gn
```

### 2. Install gn

```bash
chmod +x gn.sh
sudo cp gn.sh /usr/local/bin/gn
```

That's it. Run `gn` and it will pull your notes before opening the editor.

---

© 2026 Barney Matthews. Released under the MIT License.
