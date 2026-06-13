#!/usr/bin/env bash
# gn - Get Notes
# A zero-dependency CLI tool to sync markdown notes via GitHub or Dropbox.
# Author: Barney Matthews. License: MIT
# https://barneyme.github.io/gn-notes | https://gn-notes.pages.dev

NOTES_DIR="$HOME/gn"
CONFIG_FILE="$NOTES_DIR/gn.conf"

# --- Config ---
[ -f "$CONFIG_FILE" ] || { echo "Error: No config found at $CONFIG_FILE"; exit 1; }
chmod 600 "$CONFIG_FILE"
while IFS='=' read -r key value; do
    key="${key// /}"
    [[ "$key" =~ ^# || -z "$key" ]] && continue
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    [[ "$value" =~ ^[\"\'] ]] && value="${value:1:${#value}-2}"
    case "$key" in
        GIT_TOKEN)             GIT_TOKEN="$value" ;;
        GIT_OWNER)             GIT_OWNER="$value" ;;
        GIT_REPO)              GIT_REPO="$value" ;;
        GIT_API)               GIT_API="$value" ;;
        DROPBOX_APP_KEY)       DROPBOX_APP_KEY="$value" ;;
        DROPBOX_APP_SECRET)    DROPBOX_APP_SECRET="$value" ;;
        DROPBOX_REFRESH_TOKEN) DROPBOX_REFRESH_TOKEN="$value" ;;
        DROPBOX_PATH)          DROPBOX_PATH="$value" ;;
    esac
done < "$CONFIG_FILE"

# --- Detect Sync Engine ---
SYNC_ENGINE=""
if [ -n "$GIT_TOKEN" ] && [ -n "$GIT_OWNER" ] && [ -n "$GIT_REPO" ]; then
    SYNC_ENGINE="GITHUB"
    GIT_API="${GIT_API:-https://api.github.com/repos/${GIT_OWNER}/${GIT_REPO}/contents}"
elif [ -n "$DROPBOX_APP_KEY" ] && [ -n "$DROPBOX_APP_SECRET" ] && [ -n "$DROPBOX_REFRESH_TOKEN" ]; then
    SYNC_ENGINE="DROPBOX"
    DROPBOX_PATH="${DROPBOX_PATH:-/notes}"
    DROPBOX_PATH="/${DROPBOX_PATH#/}"
    [ "$DROPBOX_PATH" = "//" ] && DROPBOX_PATH="/"
else
    echo "Error: gn.conf is incomplete. Provide either GitHub (GIT_TOKEN, GIT_OWNER, GIT_REPO)" >&2
    echo "or Dropbox (DROPBOX_APP_KEY, DROPBOX_APP_SECRET, DROPBOX_REFRESH_TOKEN) settings." >&2
    exit 1
fi

EDITOR="${EDITOR:-nano}"

for cmd in curl grep sed awk base64 tr; do
    command -v "$cmd" &>/dev/null || { echo "Error: '$cmd' is required but not installed." >&2; exit 1; }
done

# --- Auth Initializer (Dropbox Only) ---
if [ "$SYNC_ENGINE" = "DROPBOX" ]; then
    dropbox_refresh() {
        local resp pfile
        pfile=$(mktemp); chmod 600 "$pfile"
        printf 'grant_type=refresh_token&refresh_token=%s&client_id=%s&client_secret=%s' \
            "$DROPBOX_REFRESH_TOKEN" "$DROPBOX_APP_KEY" "$DROPBOX_APP_SECRET" > "$pfile"
        resp=$(curl -s -X POST "https://api.dropbox.com/oauth2/token" --data-binary "@$pfile")
        rm -f "$pfile"
        DROPBOX_ACCESS_TOKEN=$(echo "$resp" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="access_token") {print $(i+2); exit}}')
        [ -z "$DROPBOX_ACCESS_TOKEN" ] && { echo "Error: Dropbox token refresh failed: $resp" >&2; exit 1; }
    }
    dropbox_refresh
fi

# --- Helpers ---
show_help() {
    cat <<EOF
Usage: gn [options] [note]

  -h          Show this help
  -l          List notes
  -g PATTERN  Search notes (grep)
  -t          Open today's note (YYYY-MM-DD)
  -d NOTE     Delete a note
  -r OLD NEW  Rename a note

Engine: $SYNC_ENGINE
EOF
    exit 0
}

# Writes token to a temp file so it never appears in the process list
api_curl() {
    local hdr rc
    hdr=$(mktemp); chmod 600 "$hdr"
    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        echo "Authorization: token $GIT_TOKEN" > "$hdr"
    else
        echo "Authorization: Bearer $DROPBOX_ACCESS_TOKEN" > "$hdr"
    fi
    curl -s -H "@$hdr" "$@"; rc=$?
    rm -f "$hdr"; return $rc
}

# Build the full API URL for a file (GitHub only)
api_url() {
    echo "${GIT_API}/$1"
}

# Delete a file from the remote; used by delete_note and rename_note
remote_delete() {
    local file="$1" msg="$2" url sha sha_resp http_code resp pfile REPLY

    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        url=$(api_url "$file")
        pfile=$(mktemp); chmod 600 "$pfile"

        sha_resp=$(api_curl -s "$url")
        sha=$(echo "$sha_resp" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="sha") {print $(i+2); exit}}')
        if [ -z "$sha" ]; then rm -f "$pfile"; return 0; fi
        printf '{"message":"%s","sha":"%s","branch":"main"}' "$msg" "$sha" > "$pfile"

        resp=$(api_curl -w "\n%{http_code}" -X DELETE -H "Content-Type: application/json" --data-binary "@$pfile" "$url")
        rm -f "$pfile"

        # Pure Bash Split (Bypasses line limits and subshell scope bugs completely)
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"

        [[ "$http_code" =~ ^(200|204)$ ]] || echo "Warning: Remote delete failed (HTTP $http_code)." >&2
    else
        local path arg
        path=$(printf '%s/%s' "$DROPBOX_PATH" "$file" | sed 's#//*#/#g')
        arg=$(printf '{"path":"%s"}' "$path")
        resp=$(api_curl -w "\n%{http_code}" -X POST -H "Content-Type: application/json" --data-binary "$arg" "https://api.dropboxapi.com/2/files/delete_v2")

        http_code="${resp##*$'\n'}"
        [[ "$http_code" =~ ^(200|409)$ ]] || echo "Warning: Dropbox delete failed (HTTP $http_code)." >&2
    fi
}

pull_note() {
    local file="$1" url resp http_code content REPLY

    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        url=$(api_url "$file")
        resp=$(api_curl -w "\n%{http_code}" "$url")

        # Pure Bash Split (Bypasses line limits and subshell scope bugs completely)
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"

        [ "$http_code" = "404" ] && return 0
        [ "$http_code" != "200" ] && { echo "Error: Pull failed (HTTP $http_code): $REPLY" >&2; exit 1; }

        # Token-based JSON field extraction via awk
        content=$(echo "$REPLY" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="content") {print $(i+2); exit}}' | tr -d '\\ n[:space:]"')

        [ -n "$content" ] && [ "$content" != "null" ] && {
            echo "$content" | base64 -d > "$file" 2>/dev/null \
                || echo "$content" | base64 -D > "$file" 2>/dev/null
        }
    else
        local path arg
        path=$(printf '%s/%s' "$DROPBOX_PATH" "$file" | sed 's#//*#/#g')
        arg=$(printf '{"path":"%s"}' "$path")
        http_code=$(api_curl -o "$file.tmp" -w "%{http_code}" -X POST "https://content.dropboxapi.com/2/files/download" -H "Dropbox-API-Arg: $arg")
        case "$http_code" in
            200) mv "$file.tmp" "$file" ;;
            409) rm -f "$file.tmp" ;;
            *)   rm -f "$file.tmp"; echo "Error: Dropbox pull failed (HTTP $http_code)." >&2; exit 1 ;;
        esac
    fi
}

push_note() {
    local file="$1" url sha sha_resp http_code content msg pfile REPLY
    msg="gn: update $file $(date '+%Y-%m-%d %H:%M:%S')"

    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        url=$(api_url "$file")
        content=$(base64 -w0 < "$file" 2>/dev/null || base64 < "$file" | tr -d '\n')

        pfile=$(mktemp); chmod 600 "$pfile"

        sha_resp=$(api_curl -s "$url")
        sha=$(echo "$sha_resp" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="sha") {print $(i+2); exit}}')
        if [ -n "$sha" ]; then
            printf '{"message":"%s","content":"%s","sha":"%s","branch":"main"}' \
                "$msg" "$content" "$sha" > "$pfile"
        else
            printf '{"message":"%s","content":"%s","branch":"main"}' \
                "$msg" "$content" > "$pfile"
        fi

        resp=$(api_curl -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" --data-binary "@$pfile" "$url")
        rm -f "$pfile"

        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"

        [[ "$http_code" =~ ^(200|201)$ ]] || { echo "Error: Push failed (HTTP $http_code): $REPLY" >&2; exit 1; }
    else
        local path arg
        path=$(printf '%s/%s' "$DROPBOX_PATH" "$file" | sed 's#//*#/#g')
        arg=$(printf '{"path":"%s","mode":"overwrite","autorename":false,"mute":true}' "$path")
        resp=$(api_curl -w "\n%{http_code}" -X POST "https://content.dropboxapi.com/2/files/upload" -H "Dropbox-API-Arg: $arg" -H "Content-Type: application/octet-stream" --data-binary "@$file")

        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"

        [ "$http_code" = "200" ] || { echo "Error: Dropbox push failed (HTTP $http_code): $REPLY" >&2; exit 1; }
    fi
}

list_notes() {
    echo "=== $NOTES_DIR ==="
    find "$NOTES_DIR" -type f ! -name "gn.conf" ! -name "gn.sh" ! -path '*/.*' \
        | sed "s|$NOTES_DIR/||" | sort
    exit 0
}

search_notes() {
    echo "=== Searching for: '$1' ==="
    grep -Rin "$1" "$NOTES_DIR" --exclude-dir=".git" --exclude="gn.conf" --exclude="gn.sh"
    exit 0
}

delete_note() {
    local file="$1"
    [[ "$file" != *.md ]] && file="${file}.md"
    [ -f "$NOTES_DIR/$file" ] || { echo "Error: '$file' not found."; exit 1; }
    read -r -p "Delete '$file'? This cannot be undone. [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    remote_delete "$file" "gn: delete $file"
    rm "$NOTES_DIR/$file"
    echo "Deleted '$file'."
    exit 0
}

rename_note() {
    local old="$1" new="$2"
    [[ "$old" != *.md ]] && old="${old}.md"
    [[ "$new" != *.md ]] && new="${new}.md"
    [ -f "$NOTES_DIR/$old" ]  || { echo "Error: '$old' not found."; exit 1; }
    [ -f "$NOTES_DIR/$new" ]  && { echo "Error: '$new' already exists."; exit 1; }
    cp "$NOTES_DIR/$old" "$NOTES_DIR/$new"
    push_note "$new"
    remote_delete "$old" "gn: rename $old to $new"
    mv "$NOTES_DIR/$old" "$NOTES_DIR/$new"
    echo "Renamed '$old' to '$new'."
    exit 0
}

# --- Entry Point ---
[ "$1" = "-r" ] && {
    [ -z "$2" ] || [ -z "$3" ] && { echo "Usage: gn -r OLD NEW"; exit 1; }
    rename_note "$2" "$3"
}

while getopts "hlg:td:" opt; do
    case $opt in
        h) show_help ;;
        l) list_notes ;;
        g) search_notes "$OPTARG" ;;
        t) NOTE_NAME=$(date '+%Y-%m-%d') ;;
        d) delete_note "$OPTARG" ;;
        *) show_help ;;
    esac
done
shift $((OPTIND - 1))

[ -z "$NOTE_NAME" ] && NOTE_NAME="${1:-note}"

[[ "$NOTE_NAME" == "gn.conf" || "$NOTE_NAME" == "gn.sh" ]] && {
    echo "Error: Cannot open runtime files via gn."
    exit 1
}

[[ "$NOTE_NAME" != *.md ]] && NOTE_NAME="${NOTE_NAME}.md"

mkdir -p "$NOTES_DIR"
cd "$NOTES_DIR" || { echo "Error: Cannot access $NOTES_DIR"; exit 1; }
[ "$(dirname "$NOTE_NAME")" != "." ] && mkdir -p "$(dirname "$NOTE_NAME")"

echo "Fetching... [via $SYNC_ENGINE]"
pull_note "$NOTE_NAME"

PRE_SHA=$(md5sum "$NOTE_NAME" 2>/dev/null || shasum "$NOTE_NAME" 2>/dev/null)
$EDITOR "$NOTE_NAME"

[ -f "$NOTE_NAME" ] || { echo "Note not saved. Cancelled."; exit 0; }

POST_SHA=$(md5sum "$NOTE_NAME" 2>/dev/null || shasum "$NOTE_NAME" 2>/dev/null)
if [ "$PRE_SHA" = "$POST_SHA" ]; then
    echo "No changes. Sync skipped."
else
    echo "Pushing... [via $SYNC_ENGINE]"
    push_note "$NOTE_NAME"
    echo "Done."
fi
