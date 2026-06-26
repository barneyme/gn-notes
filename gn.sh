#!/usr/bin/env bash
# gn.sh - Get Notes: sync your .txt files to a private GitHub repo via API.
# Zero dependency. No Git. Works natively on macOS, Linux, BSD, NetBSD, WSL.
# Run: chmod +x gn.sh && ./gn.sh to start
# https://gn.tuxs.me

set -euo pipefail

GN_DIR="$HOME/gn"
CONF_FILE="$GN_DIR/gn.conf"
DEFAULT_FILE="gn"

# ---------------------------------------------------------------------------
# Portability: base64
# GNU (Linux/WSL): base64 --version exits 0, decode flag is -d
# BSD/macOS/NetBSD: base64 --version exits non-zero, decode flag is -D
# b64_encode strips newlines (GNU base64 wraps at 76 chars by default)
# ---------------------------------------------------------------------------
b64_encode() {
    base64 | tr -d '\n'
}

b64_decode() {
    if base64 --version >/dev/null 2>&1; then
        base64 -d
    else
        base64 -D
    fi
}

today() {
    date +%Y-%m-%d
}

if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

info()    { printf "${CYAN}%s${RESET}\n" "$*"; }
success() { printf "${GREEN}%s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}%s${RESET}\n" "$*"; }
error()   { printf "${RED}ERROR: %s${RESET}\n" "$*" >&2; }
die()     { error "$*"; exit 1; }

load_conf() {
    # shellcheck source=/dev/null
    . "$CONF_FILE"
    : "${GN_PAT:?gn.conf is missing GN_PAT}"
    : "${GN_USER:?gn.conf is missing GN_USER}"
    : "${GN_REPO:?gn.conf is missing GN_REPO}"
}

# ---------------------------------------------------------------------------
# GitHub API helpers
# ---------------------------------------------------------------------------
api_get() {
    local path="$1"
    curl -sf \
        -H "Authorization: token $GN_PAT" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com${path}"
}

api_put() {
    local path="$1" body="$2"
    curl -sf -X PUT \
        -H "Authorization: token $GN_PAT" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://api.github.com${path}"
}

api_delete() {
    local path="$1" body="$2"
    curl -sf -X DELETE \
        -H "Authorization: token $GN_PAT" \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "https://api.github.com${path}"
}

get_sha() {
    local filename="$1"
    local response
    response=$(api_get "/repos/$GN_USER/$GN_REPO/contents/$filename" 2>/dev/null) || true
    printf '%s' "$response" \
        | grep -o '"sha": *"[^"]*"' \
        | head -1 \
        | sed 's/.*"\([^"]*\)"/\1/' \
        || true
}

# ---------------------------------------------------------------------------
# Pull a file from GitHub into ~/gn before editing.
# GitHub's API returns the content field with a space after the colon and
# literal \n sequences embedded in the JSON string value. The grep pattern
# must allow for the optional space, and the \n sequences must be stripped
# before decoding or GNU base64 (Linux/WSL) will reject the input.
# ---------------------------------------------------------------------------
pull_file() {
    local filename="$1"
    local filepath="$GN_DIR/$filename"
    local response content

    response=$(api_get "/repos/$GN_USER/$GN_REPO/contents/$filename" 2>/dev/null) || true

    if [ -n "$response" ]; then
        content=$(printf '%s' "$response" \
            | grep -o '"content": *"[^"]*"' \
            | sed 's/"content": *"//; s/"$//' \
            | sed 's/\\n//g' \
            | tr -d ' \r\n' \
            | b64_decode) || true
        if [ -n "$content" ]; then
            printf '%s' "$content" > "$filepath"
            info "Pulled $filename from $GN_USER/$GN_REPO"
        fi
    fi
}

push_file() {
    local filename="$1"
    local filepath="$GN_DIR/$filename"

    [ -f "$filepath" ] || die "File not found: $filepath"

    local content sha json msg safe_msg
    content=$(b64_encode < "$filepath")
    sha=$(get_sha "$filename")
    msg="gn: update $filename $(date '+%Y-%m-%d %H:%M')"
    safe_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')

    if [ -n "$sha" ]; then
        json=$(printf '{"message":"%s","content":"%s","sha":"%s"}' \
            "$safe_msg" "$content" "$sha")
    else
        json=$(printf '{"message":"%s","content":"%s"}' \
            "$safe_msg" "$content")
    fi

    if api_put "/repos/$GN_USER/$GN_REPO/contents/$filename" "$json" > /dev/null; then
        success "Pushed $filename to $GN_USER/$GN_REPO"
    else
        die "Push failed for $filename. Check your PAT, username, and repo name in $CONF_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Setup wizard
# ---------------------------------------------------------------------------
setup() {
    printf "\n${BOLD}gn.sh setup${RESET}\n\n"

    if [ ! -d "$GN_DIR" ]; then
        mkdir -p "$GN_DIR"
        success "Created $GN_DIR"
    fi

    if [ ! -f "$CONF_FILE" ]; then
        touch "$CONF_FILE"
        chmod 600 "$CONF_FILE"
        success "Created $CONF_FILE (chmod 600)"
    fi

    printf "  Create a Github account (if needed):    ${CYAN}https://github.com/signup${RESET}\n"
    printf "  Create a private repo:                  ${CYAN}https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository${RESET}\n"
    printf "\nYou need a GitHub Personal Access Token (classic) with ${BOLD}repo${RESET} scope.\n"
    printf "  How to create a PAT (classic):          ${CYAN}https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens${RESET}\n"
    printf "  Fine-grained tokens:                    ${CYAN}https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token${RESET}\n\n"

    printf "GitHub username: "
    read -r GN_USER
    printf "Private repo name (must already exist): "
    read -r GN_REPO
    printf "Personal Access Token (classic, repo scope): "

    if stty -echo 2>/dev/null; then
        read -r GN_PAT
        stty echo 2>/dev/null || true
        printf "\n"
    else
        read -r GN_PAT
    fi

    cat > "$CONF_FILE" <<EOF
# gn.sh configuration - chmod 600 enforced, do not share this file
GN_USER="$GN_USER"
GN_REPO="$GN_REPO"
GN_PAT="$GN_PAT"
EOF
    chmod 600 "$CONF_FILE"
    success "Config saved to $CONF_FILE"

    printf "\nVerifying credentials... "
    if curl -sf \
        -H "Authorization: token $GN_PAT" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$GN_USER/$GN_REPO" > /dev/null 2>&1; then
        success "Credentials verified. Repo is accessible."
    else
        warn "Could not reach https://api.github.com/repos/$GN_USER/$GN_REPO"
        warn "Check the PAT, username, repo name, and that the repo is private and exists."
        warn "Edit $CONF_FILE to correct any mistakes."
    fi

    install_self
}

# ---------------------------------------------------------------------------
# Self-install into a bin directory on PATH
# ---------------------------------------------------------------------------
install_self() {
    local script_path bin_dir d dest

    script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    bin_dir=""

    for d in "$HOME/bin" "$HOME/.local/bin"; do
        if [ -d "$d" ] && printf '%s' "$PATH" | grep -q "$d"; then
            bin_dir="$d"
            break
        fi
        if [ ! -d "$d" ]; then
            mkdir -p "$d"
            bin_dir="$d"
            break
        fi
    done

    if [ -z "$bin_dir" ]; then
        warn "Could not find a writable bin directory in PATH."
        printf "\nTo install manually:\n"
        printf "  ${BOLD}cp %s ~/bin/gn && chmod +x ~/bin/gn${RESET}\n" "$script_path"
        return
    fi

    dest="$bin_dir/gn"
    cp "$script_path" "$dest"
    chmod +x "$dest"
    success "Installed as $dest"
    printf "You can now run ${BOLD}gn${RESET} from anywhere.\n"

    if ! printf '%s' "$PATH" | grep -q "$bin_dir"; then
        warn "$bin_dir is not in your PATH yet."
        printf "Add this to your shell profile (.bashrc / .zshrc / .profile):\n"
        printf "  ${BOLD}export PATH=\"%s:\$PATH\"${RESET}\n" "$bin_dir"
    fi
}

# ---------------------------------------------------------------------------
# Edit workflow: pull, open editor, push
# ---------------------------------------------------------------------------
edit_and_push() {
    local name="$1"
    local filename="${name}.txt"
    local filepath="$GN_DIR/$filename"

    pull_file "$filename"
    [ -f "$filepath" ] || touch "$filepath"

    local editor="${EDITOR:-vi}"
    "$editor" "$filepath"

    push_file "$filename"
}

# ---------------------------------------------------------------------------
# -r rename
# ---------------------------------------------------------------------------
cmd_rename() {
    load_conf
    printf "Current filename (without .txt): "
    read -r old_name
    printf "New filename (without .txt): "
    read -r new_name

    local old_file="${old_name}.txt" new_file="${new_name}.txt"
    local old_path="$GN_DIR/$old_file" new_path="$GN_DIR/$new_file"

    [ -f "$old_path" ] || die "File not found: $old_path"
    [ ! -f "$new_path" ] || die "Target already exists: $new_path"

    cp "$old_path" "$new_path"
    push_file "$new_file"

    local sha
    sha=$(get_sha "$old_file")
    if [ -n "$sha" ]; then
        local json
        json=$(printf '{"message":"gn: rename %s to %s","sha":"%s"}' \
            "$old_file" "$new_file" "$sha")
        if api_delete "/repos/$GN_USER/$GN_REPO/contents/$old_file" "$json" > /dev/null; then
            success "Deleted $old_file from repo"
        else
            warn "Could not delete $old_file from repo - remove it manually if needed."
        fi
    else
        warn "$old_file not found in repo - skipping remote delete"
    fi

    rm "$old_path"
    success "Renamed $old_file to $new_file"
}

# ---------------------------------------------------------------------------
# -d delete
# ---------------------------------------------------------------------------
cmd_delete() {
    load_conf
    printf "Filename to delete (without .txt): "
    read -r name

    local filename="${name}.txt"
    local filepath="$GN_DIR/$filename"

    printf "${RED}Delete %s locally and from GitHub? [y/N]: ${RESET}" "$filename"
    read -r confirm
    case "$confirm" in [yY]) ;; *) info "Aborted."; exit 0 ;; esac

    local sha
    sha=$(get_sha "$filename")
    if [ -n "$sha" ]; then
        local json
        json=$(printf '{"message":"gn: delete %s","sha":"%s"}' "$filename" "$sha")
        if api_delete "/repos/$GN_USER/$GN_REPO/contents/$filename" "$json" > /dev/null; then
            success "Deleted $filename from repo"
        else
            warn "Remote delete failed - file may still exist on GitHub."
        fi
    else
        warn "$filename not found in repo - skipping remote delete"
    fi

    if [ -f "$filepath" ]; then
        rm "$filepath"
        success "Deleted $filepath"
    else
        warn "Local file $filepath not found"
    fi
}

# ---------------------------------------------------------------------------
# -b backup
# ---------------------------------------------------------------------------
cmd_backup() {
    local backup_dir="$HOME/gn-$(today)"

    if [ -d "$backup_dir" ]; then
        warn "Backup directory already exists: $backup_dir"
    else
        mkdir -p "$backup_dir"
    fi

    local count=0
    for f in "$GN_DIR"/*.txt; do
        [ -f "$f" ] || continue
        cp "$f" "$backup_dir/"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        warn "No .txt files found in $GN_DIR"
        rmdir "$backup_dir" 2>/dev/null || true
    else
        success "Backed up $count file(s) to $backup_dir"
    fi
}

# ---------------------------------------------------------------------------
# Guard: ensure setup has been completed
# ---------------------------------------------------------------------------
require_setup() {
    if [ ! -d "$GN_DIR" ] || [ ! -f "$CONF_FILE" ]; then
        warn "gn is not configured yet."
        printf "Run setup? [Y/n]: "
        read -r ans
        case "$ans" in [nN]) die "Aborting." ;; esac
        setup
        exit 0
    fi
    chmod 600 "$CONF_FILE"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    printf "${BOLD}gn${RESET} - Get Notes\n"
    printf "\n"
    printf "  ${BOLD}gn${RESET}              Edit gn.txt and push to GitHub\n"
    printf "  ${BOLD}gn NAME${RESET}         Edit NAME.txt and push to GitHub\n"
    printf "  ${BOLD}gn -r${RESET}           Rename a file (locally and on GitHub)\n"
    printf "  ${BOLD}gn -d${RESET}           Delete a file (locally and on GitHub)\n"
    printf "  ${BOLD}gn -b${RESET}           Backup ~/gn/*.txt to ~/gn-YYYY-MM-DD\n"
    printf "  ${BOLD}gn -h${RESET}           Show this help\n"
    printf "\n"
    printf "Config: ${CYAN}%s${RESET} (chmod 600)\n" "$CONF_FILE"
    printf "Notes:  ${CYAN}%s/*.txt${RESET}\n" "$GN_DIR"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
        -b|--backup)
            cmd_backup
            exit 0
            ;;
        -r|--rename)
            require_setup
            cmd_rename
            exit 0
            ;;
        -d|--delete)
            require_setup
            cmd_delete
            exit 0
            ;;
        -*)
            die "Unknown flag: $1. Use -h for help."
            ;;
        *)
            require_setup
            load_conf
            local name="${1:-$DEFAULT_FILE}"
            name="${name%.txt}"
            edit_and_push "$name"
            ;;
    esac
}

main "$@"
