#!/usr/bin/env bash
# gn - Get Notes
# A zero-dependency CLI note utility that syncs markdown files to GitHub
# Author: Barney Matthews. License: MIT
# https://gn-notes.pages.dev | https://github.com/barneyme/gn-notes

# --- Configuration ---
NOTES_DIR="$HOME/gn"

# --- Hardened Config Loader ---
CONFIG_FILE="$NOTES_DIR/gn.conf"
if [ -f "$CONFIG_FILE" ]; then
    chmod 600 "$CONFIG_FILE"
    # Read variables safely without sourcing arbitrary code
    while IFS='=' read -r key value; do
        # Strip leading/trailing whitespace from key
        key="${key+${key}}" # Ensures variable exists
        key=$(echo "$key" | tr -d '[:space:]')

        if [[ ! "$key" =~ ^# ]] && [[ -n "$key" ]]; then
            # 1. Trim leading and trailing whitespace from the value
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            # 2. Strip leading and trailing matching single or double quotes
            if [[ "$value" == \"*\" ]] || [[ "$value" == \'*\' ]]; then
                value="${value:1:${#value}-2}"
            fi

            eval "$key=\"\$value\""
        fi
    done < "$CONFIG_FILE"
else
    echo "Error: No config found at $CONFIG_FILE"
    echo "Create it with:"
    echo "  GH_TOKEN=yourtoken"
    echo "  GH_OWNER=yourusername"
    echo "  GH_REPO=yourrepo"
    exit 1
fi

GH_API="https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents"

if [ -z "$GH_TOKEN" ] || [ -z "$GH_OWNER" ] || [ -z "$GH_REPO" ]; then
    echo "Error: gn.conf is incomplete. Check GH_TOKEN, GH_OWNER, and GH_REPO."
    exit 1
fi

mkdir -p "$NOTES_DIR"
cd "$NOTES_DIR" || { echo "Error: Could not access $NOTES_DIR"; exit 1; }

# --- Secure curl wrapper: token passed via tempfile, never exposed in ps ---
gh_curl() {
    local hdr
    hdr=$(mktemp)
    echo "Authorization: token $GH_TOKEN" > "$hdr"
    chmod 600 "$hdr"
    curl -s -H "@$hdr" "$@"
    local rc=$?
    rm -f "$hdr"
    return $rc
}

# --- GitHub API Sync Functions ---
pull_from_github() {
    local file="$1"
    local response content http_code
    response=$(gh_curl -w "\n%{http_code}" "$GH_API/$file")
    http_code=$(echo "$response" | tail -n 1)
    response=$(echo "$response" | sed '$d')
    if [ "$http_code" = "404" ]; then
        return 0
    fi
    if [ "$http_code" != "200" ]; then
        echo "Error: pull failed (HTTP $http_code). Check your token and repo name." >&2
        exit 1
    fi

    # Secure, zero-dependency multi-line JSON extraction using pure Bash
    content=""
    while read -r line; do
        if [[ "$line" =~ \"content\":\ *\"([^\"]+)\" ]]; then
            content="${BASH_REMATCH[1]}"
            break
        elif [[ "$line" =~ \"content\":\ *\"([^\"]*)$ ]]; then
            content="${BASH_REMATCH[1]}"
            while read -r inner_line; do
                if [[ "$inner_line" =~ ^([^\"]*)\" ]]; then
                    content="${content}${BASH_REMATCH[1]}"
                    break
                else
                    content="${content}${inner_line}"
                fi
            done
            break
        fi
    done <<< "$response"

    content=$(echo "$content" | tr -d '\\n[:space:]')

    if [ -n "$content" ]; then
        echo "$content" | base64 -d > "$file" 2>/dev/null || echo "$content" | base64 -D > "$file"
    fi
}

push_to_github() {
    local file="$1"
    local sha content msg api_url sha_response push_response http_code
    api_url="$GH_API/$file"
    sha_response=$(gh_curl "$api_url")

    # Robust native regex extraction to prevent head/sed multi-platform crashes
    sha=""
    if [[ "$sha_response" =~ \"sha\":\ *\"([^\"]+)\" ]]; then
        sha="${BASH_REMATCH[1]}"
    fi

    content=$(base64 -w0 < "$file" 2>/dev/null || base64 < "$file" | tr -d '\n')
    msg="Note update: $file on $(date '+%Y-%m-%d %H:%M:%S')"
    local sha_field=""
    [ -n "$sha" ] && sha_field=",\"sha\":\"$sha\""
    push_response=$(gh_curl -w "\n%{http_code}" -X PUT "$api_url" \
        -d "{\"message\":\"$msg\",\"content\":\"$content\"$sha_field}")
    http_code=$(echo "$push_response" | tail -n 1)
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo "Error: push failed (HTTP $http_code). Your note was saved locally but not synced." >&2
        exit 1
    fi
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
    echo "  -d NOTE   Delete a note locally and from GitHub"
    echo "  -r OLD NEW  Rename a note locally and on GitHub"
    echo ""
    echo "Examples:"
    echo "  gn                  Opens index.md"
    echo "  gn log              Creates or opens log.md"
    echo "  gn work/todo        Opens work/todo.md"
    echo "  gn -g 'api key'     Searches notes for the term 'api key'"
    echo "  gn -t               Creates a note named today's date"
    exit 0
}

# --- List Files Function ---
list_notes() {
    echo "Current Notes in $NOTES_DIR:"
    if [ -d "$NOTES_DIR" ]; then
        find . -type f -not -name "gn.conf" -not -name "gn.sh" -not -path '*/.*' | sed 's|^./||' | sort
    fi
    exit 0
}

# --- Search Inside Notes Function ---
search_notes() {
    echo "Searching for '$1' inside notes..."
    grep -Rin "$1" . --exclude-dir=".git" --exclude="gn.conf" --exclude="gn.sh"
    exit 0
}

# --- Delete Note Function ---
delete_note() {
    local file="$1"
    if [[ "$file" != *.md ]]; then
        file="${file}.md"
    fi
    if [ ! -f "$NOTES_DIR/$file" ]; then
        echo "Error: '$file' not found locally."
        exit 1
    fi
    read -r -p "Delete '$file'? This cannot be undone. [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
    local sha api_url sha_response delete_response http_code
    api_url="$GH_API/$file"
    sha_response=$(gh_curl "$api_url")

    sha=""
    if [[ "$sha_response" =~ \"sha\":\ *\"([^\"]+)\" ]]; then
        sha="${BASH_REMATCH[1]}"
    fi

    if [ -n "$sha" ]; then
        delete_response=$(gh_curl -w "\n%{http_code}" -X DELETE "$api_url" \
            -d "{\"message\":\"Delete $file\",\"sha\":\"$sha\"}")
        http_code=$(echo "$delete_response" | tail -n 1)
        if [ "$http_code" != "200" ]; then
            echo "Error: Failed to delete remote file from GitHub (HTTP $http_code). Aborting local deletion." >&2
            exit 1
        fi
        echo "Deleted from GitHub."
    else
        echo "Warning: File not found on GitHub. Removing locally only."
    fi
    rm "$NOTES_DIR/$file"
    echo "Deleted '$file'."
    exit 0
}

# --- Rename Note Function ---
rename_note() {
    local old_name="$1"
    local new_name="$2"
    if [[ "$old_name" != *.md ]]; then
        old_name="${old_name}.md"
    fi
    if [[ "$new_name" != *.md ]]; then
        new_name="${new_name}.md"
    fi
    if [ ! -f "$NOTES_DIR/$old_name" ]; then
        echo "Error: '$old_name' not found locally."
        exit 1
    fi
    if [ -f "$NOTES_DIR/$new_name" ]; then
        echo "Error: '$new_name' already exists."
        exit 1
    fi
    local sha old_api_url new_api_url sha_response content push_response delete_response http_code
    old_api_url="$GH_API/$old_name"
    new_api_url="$GH_API/$new_name"
    sha_response=$(gh_curl "$old_api_url")

    sha=""
    if [[ "$sha_response" =~ \"sha\":\ *\"([^\"]+)\" ]]; then
        sha="${BASH_REMATCH[1]}"
    fi

    content=$(base64 -w0 < "$NOTES_DIR/$old_name" 2>/dev/null || base64 < "$NOTES_DIR/$old_name" | tr -d '\n')

    # Step 1: Put new file on GitHub
    push_response=$(gh_curl -w "\n%{http_code}" -X PUT "$new_api_url" \
        -d "{\"message\":\"Rename $old_name to $new_name\",\"content\":\"$content\"}")
    http_code=$(echo "$push_response" | tail -n 1)
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        echo "Error: Failed to create '$new_name' on GitHub (HTTP $http_code). No changes made." >&2
        exit 1
    fi

    # Step 2: Delete old file on GitHub ONLY if the creation step fully succeeded
    if [ -n "$sha" ]; then
        delete_response=$(gh_curl -w "\n%{http_code}" -X DELETE "$old_api_url" \
            -d "{\"message\":\"Rename $old_name to $new_name\",\"sha\":\"$sha\"}")
        http_code=$(echo "$delete_response" | tail -n 1)
        if [ "$http_code" != "200" ]; then
            echo "Warning: New note created on GitHub, but old note could not be removed automatically." >&2
        fi
    fi

    # Step 3: Shift local state
    mv "$NOTES_DIR/$old_name" "$NOTES_DIR/$new_name"
    echo "Renamed '$old_name' to '$new_name'."
    exit 0
}

# --- Handle Intercepted Direct Flags First ---
if [ "$1" = "-r" ]; then
    if [ -z "$2" ] || [ -z "$3" ]; then
        echo "Error: -r requires two arguments: gn -r OLD NEW"
        exit 1
    fi
    rename_note "$2" "$3"
fi

# --- Parse Remaining Flags Safely ---
while getopts "hlg:td:" opt; do
    case ${opt} in
        h ) show_help ;;
        l ) list_notes ;;
        g ) search_notes "$OPTARG" ;;
        t ) NOTE_NAME=$(date '+%Y-%m-%d') ;;
        d ) delete_note "$OPTARG" ;;
        \? ) show_help ;;
    esac
done
shift $((OPTIND -1))

# If -t wasn't passed, get note name from command line arguments
if [ -z "$NOTE_NAME" ]; then
    NOTE_NAME="${1:-index}"
fi

if [[ "$NOTE_NAME" == "gn.conf" || "$NOTE_NAME" == "gn.sh" ]]; then
    echo "Error: Protection rule triggered. Cannot touch runtime target files via gn loop."
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
