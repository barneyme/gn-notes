#!/usr/bin/env bash

# --- 1. Configuration ---
NOTES_DIR="$HOME/gn"
REMOTE_BRANCH="main"

mkdir -p "$NOTES_DIR"
cd "$NOTES_DIR" || { echo "Error: Could not access $NOTES_DIR"; exit 1; }

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
    echo "📂 Current Notes in $NOTES_DIR:"
    if [ -d "$NOTES_DIR" ]; then
        find . -type f -not -path '*/.*' | sed 's|^./||' | sort
    fi
    exit 0
}

# --- Search Inside Notes Function ---
search_notes() {
    echo "🔍 Searching for '$1' inside notes..."
    grep -Rin "$1" . --exclude-dir=".git"
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

if [[ "$NOTE_NAME" != *.md ]]; then
    NOTE_NAME="${NOTE_NAME}.md"
fi

NOTE_DIR_PATH=$(dirname "$NOTE_NAME")
if [ "$NOTE_DIR_PATH" != "." ]; then
    mkdir -p "$NOTE_DIR_PATH"
fi

# --- Sync From Cloud ---
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "🔄 Fetching latest cloud updates..."
    git pull origin "$REMOTE_BRANCH" --ff-only --quiet
fi

# --- 3. Open the Editor ---
${EDITOR:-nano} "$NOTE_NAME"

# --- 4. Sync Back to GitHub ---
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if [[ -n $(git status --porcelain) ]]; then
        echo "🚀 Syncing changes to GitHub..."
        git add -A
        git commit -m "Note update: $NOTE_NAME on $(date '+%Y-%m-%d %H:%M:%S')" --quiet
        git push origin "$REMOTE_BRANCH" --quiet
        echo "✅ Sync complete!"
    else
        echo "💤 No changes detected. Notes are up to date."
    fi
else
    echo "⚠️ Warning: This directory is not a Git repository yet. Sync skipped."
fi