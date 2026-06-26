# gn // get notes

Zero-dependency plain-text notes, synced to a private GitHub repo.

`gn` is a simple bash script that opens a plain-text note in `$EDITOR` and pushes it to a private GitHub repo via the API. No git, no daemons, no heavy apps to install—just `curl` and a local folder at `~/gn`.

---

## Download

[↓ gn.sh - save to `~/bin/gn`, `chmod +x`](./gn.sh)

---

## Setup

1. Download [gn.sh](./gn.sh) above and make it executable:
   ```bash
   mv gn.sh ~/bin/gn && chmod +x ~/bin/gn
   ```

2. Create a private GitHub repository to hold your notes (named `gn`, or anything you like).

3. Generate a GitHub Personal Access Token (classic) with the `repo` scope.
   - [🔗 GitHub PAT Token Docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
   - [🔑 Direct Token Generation Link](https://github.com/settings/tokens/new?scopes=repo&description=gn-cli)
   - Credentials are saved into `~/gn/gn.conf` with `chmod 600` permissions—only your local user can read the file.

4. Run the script. If no configuration file is found, it will run the interactive setup wizard:
   ```bash
   $ gn
   gn.sh setup
   GitHub username: your-username
   Private repo name (must already exist): gn
   Personal Access Token (classic, repo scope): ************
   Verifying credentials... Config saved. Repo is accessible.
   ```
   The setup wizard also installs `gn` into `~/bin` or `~/.local/bin` so you can run it from anywhere.

---

## Usage

```bash
gn [options] [name]
```

- Open a note: `gn my-note`
- List all notes: `gn -l`
- Sync all notes: `gn -s`
- Delete a note: `gn -d my-note`

---

## Notes

- Sync is last-write-wins. There's no merge or conflict resolution.
- Notes are stored as `.txt` files in `~/gn/`.

---

## Source

The full script—copy it directly if you'd rather not download the file.

```bash
#!/bin/bash
# (Full script content here)
```

---
[gn.tuxs.me](https://gn.tuxs.me)
