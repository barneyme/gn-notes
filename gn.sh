#!/usr/bin/env bash

# --- Configuration ---
NOTES_DIR="$HOME/gn"

# --- Load Config ---
CONFIG_FILE="$NOTES_DIR/gn.conf"
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
else
    echo "Error: No config found at $CONFIG_FILE"
    echo "Create it with:"
    echo "  GH_TOKEN=yourtoken"
    echo "  GH_OWNER=yourusername"
    echo "  GH_REPO=yourrepo"
    exit 1
fi

GH_API="https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents"

mkdir -p "$NOTES_DIR"
cd "$NOTES_DIR" || { echo "Error: Could not access $NOTES_DIR"; exit 1; }

# --- GitHub API Sync Functions (used when git is not available) ---
pull_from_github() {
    local file="$1"
    local response content
    response=$(curl -s -H "Authorization: token $GH_TOKEN" "$GH_API/$file")
    content=$(echo "$response" | grep '"content"' | sed 's/.*"content": *"\(.*\)".*/\1/' | tr -d '\\n')
    if [ -n "$content" ]; then
        echo "$content" | base64 -d > "$file" 2>/dev/null || echo "$content" | base64 -D > "$file"
    fi
}

push_to_github() {
    local file="$1"
    local sha content msg api_url
    api_url="$GH_API/$file"
    sha=$(curl -s -H "Authorization: token $GH_TOKEN" "$api_url" | grep '"sha"' | head -1 | sed 's/.*"sha": *"\([^"]*\)".*/\1/')
    content=$(base64 -w0 < "$file" 2>/dev/null || base64 < "$file")
    msg="Note update: $file on $(date '+%Y-%m-%d %H:%M:%S')"
    local sha_field=""
    [ -n "$sha" ] && sha_field=",\"sha\":\"$sha\""
    curl -s -X PUT -H "Authorization: token $GH_TOKEN" "$api_url" \
        -d "{\"message\":\"$msg\",\"content\":\"$content\"$sha_field}" > /dev/null
}

# --- Help Text Function ---
show_help() {
    echo "Usage: gn [options] [note_name]"
    echo ""
    echo "Options:"
    echo "  -h        Show this help message"
    echo "  -l        List all notes in your notes directory"
    echo "  -g QUERY  Search for text across all notes (grep)"
    echo "  -t        Quickly open today's journal note (YYYY-MM-DD.md)"
    echo ""
    echo "Examples:"
    echo "  gn                  Opens index.md"
    echo "  gn daily-log        Opens daily-log.md"
    echo "  gn work/todo        Opens work/todo.md"
    echo "  gn -g 'api key'     Searches notes for the term 'api key'"
    echo "  gn -t               Opens a scratchpad for today's date"
    exit 0
}

# --- List Files Function ---
list_notes() {
    echo "Current Notes in $NOTES_DIR:"
    if [ -d "$NOTES_DIR" ]; then
        find . -type f -not -name "gn.conf" -not -path '*/.*' | sed 's|^./||' | sort
    fi
    exit 0
}

# --- Search Inside Notes Function ---
search_notes() {
    echo "Searching for '$1' inside notes..."
    grep -Rin "$1" . --exclude-dir=".git" --exclude="gn.conf"
    exit 0
}

# --- Parse Flags ---
while getopts "hlg:t" opt; do
    case ${opt} in
        h ) show_help ;;
        l ) list_notes ;;
        g ) search_notes "$OPTARG" ;;
        t ) NOTE_NAME=$(date '+%Y-%m-%d') ;;
        \? ) show_help ;;
    esac
done
shift $((OPTIND -1))

# If -t wasn't passed, get note name from command line arguments
if [ -z "$NOTE_NAME" ]; then
    NOTE_NAME="${1:-index}"
fi

if [[ "$NOTE_NAME" == "gn.conf" ]]; then
    echo "Error: Protection rule triggered. Cannot edit configuration file via gn script loop."
    exit 1
fi

if [[ "$NOTE_NAME" != *.md ]]; then
    NOTE_NAME="${NOTE_NAME}.md"
fi

NOTE_DIR_PATH=$(dirname "$NOTE_NAME")
if [ "$NOTE_DIR_PATH" != "." ]; then
    mkdir -p "$NOTE_DIR_PATH"
fi

# --- Sync From Cloud ---
echo "Fetching latest cloud updates..."
pull_from_github "$NOTE_NAME"

# --- Open the Editor ---
${EDITOR:-nano} "$NOTE_NAME"

# --- Sync Back to GitHub ---
echo "Syncing changes to GitHub..."
push_to_github "$NOTE_NAME"
echo "Sync complete!"