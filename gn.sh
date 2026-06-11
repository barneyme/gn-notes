#!/usr/bin/env bash
# gn - Get Notes
# A zero-dependency CLI tool to manage and sync markdown notes to cloud git providers.
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
        GIT_PROVIDER) GIT_PROVIDER="$value" ;;
        GIT_TOKEN)    GIT_TOKEN="$value"    ;;
        GIT_OWNER)    GIT_OWNER="$value"    ;;
        GIT_REPO)     GIT_REPO="$value"     ;;
        GIT_API)      GIT_API="$value"      ;;
        GH_TOKEN)     GH_TOKEN="$value"     ;;
        GH_OWNER)     GH_OWNER="$value"     ;;
        GH_REPO)      GH_REPO="$value"      ;;
    esac
done < "$CONFIG_FILE"

# Backward compatibility with older GH_* variable names
[ -z "$GIT_PROVIDER" ] && [ -n "$GH_TOKEN" ] && GIT_PROVIDER="github"
[ -z "$GIT_TOKEN" ]    && GIT_TOKEN="$GH_TOKEN"
[ -z "$GIT_OWNER" ]    && GIT_OWNER="$GH_OWNER"
[ -z "$GIT_REPO" ]     && GIT_REPO="$GH_REPO"

if [ -z "$GIT_PROVIDER" ] || [ -z "$GIT_TOKEN" ] || [ -z "$GIT_OWNER" ] || [ -z "$GIT_REPO" ]; then
    echo "Error: gn.conf is incomplete. Check GIT_PROVIDER, GIT_TOKEN, GIT_OWNER, and GIT_REPO."
    exit 1
fi

GIT_PROVIDER=$(echo "$GIT_PROVIDER" | tr '[:upper:]' '[:lower:]')

# --- API URL ---
if [ -z "$GIT_API" ]; then
    case "$GIT_PROVIDER" in
        gitlab)   GIT_API="https://gitlab.com/api/v4/projects/$(echo "${GIT_OWNER}/${GIT_REPO}" | sed 's/\//%2F/g')/repository/files" ;;
        codeberg) GIT_API="https://codeberg.org/api/v1/repos/${GIT_OWNER}/${GIT_REPO}/contents" ;;
        *)        GIT_API="https://api.github.com/repos/${GIT_OWNER}/${GIT_REPO}/contents" ;;
    esac
fi

EDITOR="${EDITOR:-nano}"

for cmd in curl grep sed awk base64 tr; do
    command -v "$cmd" &>/dev/null || { echo "Error: '$cmd' is required but not installed." >&2; exit 1; }
done

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

Defaults to 'note' if no note is given.
EOF
    exit 0
}

# Writes token to a temp file so it never appears in the process list
api_curl() {
    local hdr rc
    hdr=$(mktemp); chmod 600 "$hdr"
    [ "$GIT_PROVIDER" = "gitlab" ] \
        && echo "PRIVATE-TOKEN: $GIT_TOKEN" > "$hdr" \
        || echo "Authorization: token $GIT_TOKEN" > "$hdr"
    curl -s -H "@$hdr" "$@"; rc=$?
    rm -f "$hdr"; return $rc
}

# URL-encode slashes in a file path (GitLab requires this)
encode_path() { echo "$1" | sed 's/\//%2F/g'; }

# Build the full API URL for a file
api_url() {
    local file="$1"
    [ "$GIT_PROVIDER" = "gitlab" ] \
        && echo "${GIT_API}/$(encode_path "$file")" \
        || echo "${GIT_API}/$file"
}

# Delete a file from the remote; used by delete_note and rename_note
remote_delete() {
    local file="$1" msg="$2" url sha sha_resp http_code resp pfile REPLY
    url=$(api_url "$file")
    pfile=$(mktemp); chmod 600 "$pfile"

    if [ "$GIT_PROVIDER" = "gitlab" ]; then
        printf '{"branch":"main","commit_message":"%s"}' "$msg" > "$pfile"
    else
        sha_resp=$(api_curl -s "$url")
        sha=$(echo "$sha_resp" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="sha") {print $(i+2); exit}}')
        if [ -z "$sha" ]; then rm -f "$pfile"; return 0; fi
        printf '{"message":"%s","sha":"%s","branch":"main"}' "$msg" "$sha" > "$pfile"
    fi

    resp=$(api_curl -w "\n%{http_code}" -X DELETE -H "Content-Type: application/json" --data-binary "@$pfile" "$url")
    rm -f "$pfile"

    # Pure Bash Split (Bypasses line limits and subshell scope bugs completely)
    http_code="${resp##*$'\n'}"
    REPLY="${resp%$'\n'*}"

    [[ "$http_code" =~ ^(200|204)$ ]] || echo "Warning: Remote delete failed (HTTP $http_code)." >&2
}

pull_note() {
    local file="$1" url resp http_code content REPLY
    url=$(api_url "$file")
    [ "$GIT_PROVIDER" = "gitlab" ] && url="${url}?ref=main"

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
}

push_note() {
    local file="$1" url sha sha_resp http_code req_method resp content msg pfile REPLY
    msg="gn: update $file $(date '+%Y-%m-%d %H:%M:%S')"
    url=$(api_url "$file")

    if [ "$GIT_PROVIDER" = "codeberg" ]; then
        content=$(base64 < "$file" | tr -d '\n\r')
    else
        content=$(base64 -w0 < "$file" 2>/dev/null || base64 < "$file" | tr -d '\n')
    fi

    pfile=$(mktemp); chmod 600 "$pfile"

    if [ "$GIT_PROVIDER" = "gitlab" ]; then
        resp=$(api_curl -w "\n%{http_code}" "${url}?ref=main")
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"
        [ "$http_code" = "200" ] && req_method="PUT" || req_method="POST"
        printf '{"branch":"main","commit_message":"%s","content":"%s","encoding":"base64"}' \
            "$msg" "$content" > "$pfile"
    else
        sha_resp=$(api_curl -s "$url")
        sha=$(echo "$sha_resp" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="sha") {print $(i+2); exit}}')
        req_method="PUT"
        if [ -n "$sha" ]; then
            printf '{"message":"%s","content":"%s","sha":"%s","branch":"main"}' \
                "$msg" "$content" "$sha" > "$pfile"
        else
            printf '{"message":"%s","content":"%s","branch":"main"}' \
                "$msg" "$content" > "$pfile"
        fi
    fi

    resp=$(api_curl -w "\n%{http_code}" -X "$req_method" -H "Content-Type: application/json" --data-binary "@$pfile" "$url")
    rm -f "$pfile"

    http_code="${resp##*$'\n'}"
    REPLY="${resp%$'\n'*}"

    [[ "$http_code" =~ ^(200|201)$ ]] || { echo "Error: Push failed (HTTP $http_code): $REPLY" >&2; exit 1; }
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

echo "Fetching..."
pull_note "$NOTE_NAME"

PRE_SHA=$(md5sum "$NOTE_NAME" 2>/dev/null || shasum "$NOTE_NAME" 2>/dev/null)
$EDITOR "$NOTE_NAME"

[ -f "$NOTE_NAME" ] || { echo "Note not saved. Cancelled."; exit 0; }

POST_SHA=$(md5sum "$NOTE_NAME" 2>/dev/null || shasum "$NOTE_NAME" 2>/dev/null)
if [ "$PRE_SHA" = "$POST_SHA" ]; then
    echo "No changes. Sync skipped."
else
    echo "Pushing..."
    push_note "$NOTE_NAME"
    echo "Done."
fi
