#!/usr/bin/env bash
# gn - get Notes
# A zero-dependency CLI tool to sync markdown notes via WebDAV, GitHub, or Dropbox.
# Web: gn-notes.pages.dev. Author: Barney Matthews. License: MIT

NOTES_DIR="$HOME/gn"
CONFIG_FILE="$NOTES_DIR/gn.conf"

mkdir -p "$NOTES_DIR"

for cmd in curl grep sed awk base64 tr; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required but not installed." >&2; exit 1; }
done

# --- Config ---
if [ -f "$CONFIG_FILE" ]; then
    chmod 600 "$CONFIG_FILE"
    while IFS='=' read -r key value; do
        key=$(echo "$key" | tr -d ' ')
        [ -z "$key" ] && continue
        case "$key" in \#*) continue ;; esac

        value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]*#.*//')
        case "$value" in \'*\'|\"*\" ) value=$(echo "$value" | sed 's/^.\(.*\).$/\1/') ;; esac

        case "$key" in
            gn_USER)               gn_USER="$value" ;;
            gn_PASS)               gn_PASS="$value" ;;
            gn_PATH)               gn_PATH="$value" ;;
            gn_URL)                gn_URL="$value" ;;
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
fi

# --- First-run / reconfigure setup ---
if [ -z "$gn_USER" ] && [ -z "$GIT_TOKEN" ] && [ -z "$DROPBOX_APP_KEY" ]; then
    echo "No config found at $CONFIG_FILE - let's set one up."
    echo "Select your provider:"
    echo "1) Koofr (WebDAV)"
    echo "2) Custom WebDAV Server"
    echo "3) GitHub"
    echo "4) Dropbox"
    printf "Choice [1-4]: "
    read -r provider_choice

    case "$provider_choice" in
        2)
            printf "WebDAV Server URL (e.g., https://example.com/remote.php/dav/files/user/): "
            read -r gn_URL
            printf "Username: "
            read -r gn_USER
            printf "App Password (input hidden): "
            stty -echo; read -r gn_PASS; stty echo; echo
            printf "Remote notes folder inside WebDAV [/notes]: "
            read -r gn_PATH
            gn_PATH="${gn_PATH:-/notes}"
            ;;
        3)
            printf "GitHub Personal Access Token (input hidden): "
            stty -echo; read -r GIT_TOKEN; stty echo; echo
            printf "GitHub username (repo owner): "
            read -r GIT_OWNER
            printf "Repository name: "
            read -r GIT_REPO
            ;;
        4)
            printf "Dropbox App Key: "
            read -r DROPBOX_APP_KEY
            printf "Dropbox App Secret (input hidden): "
            stty -echo; read -r DROPBOX_APP_SECRET; stty echo; echo
            printf "Dropbox Refresh Token (input hidden): "
            stty -echo; read -r DROPBOX_REFRESH_TOKEN; stty echo; echo
            printf "Remote notes folder in Dropbox [/notes]: "
            read -r DROPBOX_PATH
            DROPBOX_PATH="${DROPBOX_PATH:-/notes}"
            ;;
        *)
            gn_URL="https://app.koofr.net/dav/Koofr"
            printf "Koofr email/username: "
            read -r gn_USER
            printf "Koofr app password (input hidden): "
            stty -echo; read -r gn_PASS; stty echo; echo
            printf "Remote notes folder [/notes]: "
            read -r gn_PATH
            gn_PATH="${gn_PATH:-/notes}"
            ;;
    esac

    printf "Save this config for future runs? [Y/n] "
    read -r save
    case "$save" in
        [Nn]|[Nn][Oo]) echo "Using credentials for this session only." ;;
        *)
            umask 077
            {
                if [ -n "$GIT_TOKEN" ]; then
                    printf 'GIT_TOKEN=%s\nGIT_OWNER=%s\nGIT_REPO=%s\n' "$GIT_TOKEN" "$GIT_OWNER" "$GIT_REPO"
                elif [ -n "$DROPBOX_APP_KEY" ]; then
                    cat <<EOF
DROPBOX_APP_KEY=$DROPBOX_APP_KEY
DROPBOX_APP_SECRET=$DROPBOX_APP_SECRET
DROPBOX_REFRESH_TOKEN=$DROPBOX_REFRESH_TOKEN
DROPBOX_PATH=$DROPBOX_PATH
EOF
                else
                    printf 'gn_URL=%s\ngn_USER=%s\ngn_PASS=%s\ngn_PATH=%s\n' "$gn_URL" "$gn_USER" "$gn_PASS" "$gn_PATH"
                fi
            } > "$CONFIG_FILE"
            chmod 600 "$CONFIG_FILE"
            echo "Saved to $CONFIG_FILE"
            ;;
    esac
fi

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
elif [ -n "$gn_USER" ] && [ -n "$gn_PASS" ] && [ -n "$gn_URL" ]; then
    SYNC_ENGINE="WEBDAV"
    gn_URL="${gn_URL%/}"
    gn_PATH="${gn_PATH:-/notes}"
    case "$gn_PATH" in /*) ;; *) gn_PATH="/$gn_PATH" ;; esac
    [ "$gn_PATH" = "//" ] && gn_PATH="/"
else
    echo "Error: gn.conf is incomplete. Provide WebDAV (gn_URL, gn_USER, gn_PASS)," >&2
    echo "GitHub (GIT_TOKEN, GIT_OWNER, GIT_REPO), or Dropbox (DROPBOX_APP_KEY," >&2
    echo "DROPBOX_APP_SECRET, DROPBOX_REFRESH_TOKEN) credentials." >&2
    exit 1
fi

# --- Dropbox Auth Init ---
if [ "$SYNC_ENGINE" = "DROPBOX" ]; then
    dropbox_refresh() {
        local resp pfile
        pfile=$(mktemp); chmod 600 "$pfile"
        cat <<EOF > "$pfile"
grant_type=refresh_token&refresh_token=${DROPBOX_REFRESH_TOKEN}&client_id=${DROPBOX_APP_KEY}&client_secret=${DROPBOX_APP_SECRET}
EOF
        resp=$(curl -s -X POST "https://api.dropbox.com/oauth2/token" --data-binary "@$pfile")
        rm -f "$pfile"
        DROPBOX_ACCESS_TOKEN=$(echo "$resp" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="access_token") {print $(i+2); exit}}')
        [ -z "$DROPBOX_ACCESS_TOKEN" ] && { echo "Error: Dropbox token refresh failed: $resp" >&2; exit 1; }
    }
    dropbox_refresh
fi

EDITOR="${EDITOR:-nano}"

# --- Helpers ---
show_help() {
    local remote_info
    case "$SYNC_ENGINE" in
        GITHUB)  remote_info="GitHub: ${GIT_OWNER}/${GIT_REPO}" ;;
        DROPBOX) remote_info="Dropbox: ${DROPBOX_PATH}" ;;
        *)       remote_info="WebDAV: ${gn_URL}${gn_PATH}" ;;
    esac
    cat <<EOF
Usage: gn [options] [note]

  -h          Show this help
  -t          Open today's note (YYYY-MM-DD)
  -d NOTE     Delete a note (local + remote)
  -r OLD NEW  Rename a note (local + remote)
  -s          Sync (pull) all remote notes down to local directory
  -c          Clear saved credentials and reconfigure

  Browse local notes:
    ls ~/gn                       List notes
    grep -r "keyword" ~/gn        Search note contents
    find ~/gn -name "*.md"        Find notes by filename

Engine: $SYNC_ENGINE
Remote: $remote_info
EOF
    exit 0
}

api_curl() {
    local hdr rc
    if [ "$SYNC_ENGINE" = "WEBDAV" ]; then
        local nf host
        host=$(echo "$gn_URL" | awk -F/ '{print $3}')
        nf=$(mktemp); chmod 600 "$nf"
        printf 'machine %s\nlogin %s\npassword %s\n' "$host" "$gn_USER" "$gn_PASS" > "$nf"
        curl -s --netrc-file "$nf" "$@"; rc=$?
        rm -f "$nf"; return $rc
    else
        hdr=$(mktemp); chmod 600 "$hdr"
        if [ "$SYNC_ENGINE" = "GITHUB" ]; then
            echo "Authorization: token $GIT_TOKEN" > "$hdr"
        else
            echo "Authorization: Bearer $DROPBOX_ACCESS_TOKEN" > "$hdr"
        fi
        curl -s -H "@$hdr" "$@"; rc=$?
        rm -f "$hdr"; return $rc
    fi
}

urlenc() {
    local s="$1" out="" c i
    for (( i=0; i<${#s}; i++ )); do
        c="${s:$i:1}"
        case "$c" in
            [a-zA-Z0-9./_-]) out+="$c" ;;
            *) out+=$(printf '%%%02X' "'$c") ;;
        esac
    done
    echo "$out"
}

urldec() {
    echo "$1" | awk '{
        gsub(/\+/, " ");
        while (match($0, /%[0-9a-fA-F]{2}/)) {
            hex = substr($0, RSTART+1, 2);
            dec = 0;
            for (i=1; i<=2; i++) {
                c = substr(hex, i, 1);
                if (c ~ /[A-F]/) { dec = dec * 16 + (index("ABCDEF", c) + 9) }
                else if (c ~ /[a-f]/) { dec = dec * 16 + (index("abcdef", c) + 9) }
                else { dec = dec * 16 + c }
            }
            printf "%s%c", substr($0, 1, RSTART-1), dec;
            $0 = substr($0, RSTART+RLENGTH);
        }
        print $0;
    }'
}

get_file_hash() {
    if command -v md5sum >/dev/null 2>&1; then md5sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then md5 -q "$1" 2>/dev/null || md5 "$1" 2>/dev/null | awk '{print $1}'
    else ls -ln "$1" 2>/dev/null | awk '{print $5,$6,$7,$8}'
    fi
}

remote_url() { echo "${gn_URL}$(urlenc "${gn_PATH}/$1")"; }

remote_mkdir() {
    local dir="$1" path="" part parts target
    if [ -z "$dir" ] || [ "$dir" = "." ]; then target="$gn_PATH"; else target="$gn_PATH/$dir"; fi
    IFS='/' read -ra parts <<< "$target"
    for part in "${parts[@]}"; do
        [ -z "$part" ] && continue
        path="$path/$part"
        api_curl -X MKCOL "${gn_URL}$(urlenc "$path")" -o /dev/null
    done
}

pull_note() {
    local file="$1"

    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        local url resp http_code content REPLY
        url="${GIT_API}/$file"
        resp=$(api_curl -w "\n%{http_code}" "$url")
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"
        [ "$http_code" = "404" ] && return 0
        [ "$http_code" != "200" ] && { echo "Error: Pull failed (HTTP $http_code): $REPLY" >&2; exit 1; }
        content=$(echo "$REPLY" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="content") {print $(i+2); exit}}' | tr -d '\\ n[:space:]"')
        [ -n "$content" ] && [ "$content" != "null" ] && {
            echo "$content" | base64 -d > "$file" 2>/dev/null \
                || echo "$content" | base64 -D > "$file" 2>/dev/null
        }

    elif [ "$SYNC_ENGINE" = "DROPBOX" ]; then
        local path arg http_code
        path=$(printf '%s/%s' "$DROPBOX_PATH" "$file" | sed 's#//*#/#g')
        arg=$(printf '{"path":"%s"}' "$path")
        http_code=$(api_curl -o "$file.tmp" -w "%{http_code}" -X POST \
            "https://content.dropboxapi.com/2/files/download" \
            -H "Dropbox-API-Arg: $arg")
        case "$http_code" in
            200) mv "$file.tmp" "$file" ;;
            409) rm -f "$file.tmp" ;;
            *)   rm -f "$file.tmp"; echo "Error: Dropbox pull failed (HTTP $http_code)." >&2; exit 1 ;;
        esac

    else
        local url http_code
        url=$(remote_url "$file")
        http_code=$(api_curl -w "%{http_code}" -o "$file" "$url")
        case "$http_code" in
            200) ;;
            404) rm -f "$file" ;;
            *) echo "Error: Pull failed (HTTP $http_code)." >&2; exit 1 ;;
        esac
    fi
}

push_note() {
    local file="$1"

    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        local url sha sha_resp http_code content msg pfile REPLY
        msg="gn: update $file $(date '+%Y-%m-%d %H:%M:%S')"
        url="${GIT_API}/$file"
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

    elif [ "$SYNC_ENGINE" = "DROPBOX" ]; then
        local path arg resp http_code REPLY
        path=$(printf '%s/%s' "$DROPBOX_PATH" "$file" | sed 's#//*#/#g')
        arg=$(printf '{"path":"%s","mode":"overwrite","autorename":false,"mute":true}' "$path")
        resp=$(api_curl -w "\n%{http_code}" -X POST \
            "https://content.dropboxapi.com/2/files/upload" \
            -H "Dropbox-API-Arg: $arg" \
            -H "Content-Type: application/octet-stream" \
            --data-binary "@$file")
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"
        [ "$http_code" = "200" ] || { echo "Error: Dropbox push failed (HTTP $http_code): $REPLY" >&2; exit 1; }

    else
        local url http_code dir
        dir=$(dirname "$file")
        remote_mkdir "$dir"
        url=$(remote_url "$file")
        http_code=$(api_curl -w "%{http_code}" -o /dev/null -X PUT --data-binary "@$file" "$url")
        case "$http_code" in
            200|201|204) ;;
            *) echo "Error: Push failed (HTTP $http_code)." >&2; exit 1 ;;
        esac
    fi
}

remote_delete() {
    local file="$1" msg="${2:-gn: delete $1}"

    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        local url sha sha_resp http_code resp pfile REPLY
        url="${GIT_API}/$file"
        pfile=$(mktemp); chmod 600 "$pfile"
        sha_resp=$(api_curl -s "$url")
        sha=$(echo "$sha_resp" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="sha") {print $(i+2); exit}}')
        if [ -z "$sha" ]; then rm -f "$pfile"; return 0; fi
        printf '{"message":"%s","sha":"%s","branch":"main"}' "$msg" "$sha" > "$pfile"
        resp=$(api_curl -w "\n%{http_code}" -X DELETE -H "Content-Type: application/json" --data-binary "@$pfile" "$url")
        rm -f "$pfile"
        http_code="${resp##*$'\n'}"
        [[ "$http_code" =~ ^(200|204)$ ]] || echo "Warning: Remote delete failed (HTTP $http_code)." >&2

    elif [ "$SYNC_ENGINE" = "DROPBOX" ]; then
        local path arg resp http_code
        path=$(printf '%s/%s' "$DROPBOX_PATH" "$file" | sed 's#//*#/#g')
        arg=$(printf '{"path":"%s"}' "$path")
        resp=$(api_curl -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" --data-binary "$arg" \
            "https://api.dropboxapi.com/2/files/delete_v2")
        http_code="${resp##*$'\n'}"
        [[ "$http_code" =~ ^(200|409)$ ]] || echo "Warning: Dropbox delete failed (HTTP $http_code)." >&2

    else
        local url http_code
        url=$(remote_url "$file")
        http_code=$(api_curl -w "%{http_code}" -o /dev/null -X DELETE "$url")
        case "$http_code" in 200|204|404) ;; *) echo "Warning: Remote delete failed (HTTP $http_code)." >&2 ;; esac
    fi
}

remote_rename() {
    local old="$1" new="$2"

    if [ "$SYNC_ENGINE" = "GITHUB" ] || [ "$SYNC_ENGINE" = "DROPBOX" ]; then
        cp "$NOTES_DIR/$old" "$NOTES_DIR/$new"
        push_note "$new"
        remote_delete "$old" "gn: rename $old to $new"
        rm -f "$NOTES_DIR/$new"
    else
        local src dst http_code dir
        dir=$(dirname "$new")
        remote_mkdir "$dir"
        src=$(remote_url "$old")
        dst=$(remote_url "$new")
        http_code=$(api_curl -w "%{http_code}" -o /dev/null -X MOVE -H "Destination: $dst" -H "Overwrite: F" "$src")
        case "$http_code" in 201|204|412|404) ;; *) echo "Warning: Remote rename failed (HTTP $http_code)." >&2 ;; esac
    fi
}

delete_note() {
    local file="$1"
    case "$file" in *.md) ;; *) file="${file}.md" ;; esac
    [ -f "$NOTES_DIR/$file" ] || { echo "Error: '$file' not found."; exit 1; }
    printf "Delete '%s'? This cannot be undone. [y/N] " "$file"
    read -r confirm
    case "$confirm" in [Yy]|[Yy][Ee][Ss]) ;; *) echo "Aborted."; exit 0 ;; esac
    remote_delete "$file" "gn: delete $file"
    rm "$NOTES_DIR/$file"
    echo "Deleted '$file'."
    exit 0
}

rename_note() {
    local old="$1" new="$2"
    case "$old" in *.md) ;; *) old="${old}.md" ;; esac
    case "$new" in *.md) ;; *) new="${new}.md" ;; esac
    [ -f "$NOTES_DIR/$old" ] || { echo "Error: '$old' not found."; exit 1; }
    [ -f "$NOTES_DIR/$new" ] && { echo "Error: '$new' already exists."; exit 1; }
    remote_rename "$old" "$new"
    [ "$(dirname "$new")" != "." ] && mkdir -p "$NOTES_DIR/$(dirname "$new")"
    mv "$NOTES_DIR/$old" "$NOTES_DIR/$new"
    echo "Renamed '$old' to '$new'."
    exit 0
}

sync_all_remote() {
    echo "Fetching remote file list... [$SYNC_ENGINE]"

    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        local resp http_code REPLY paths path
        resp=$(api_curl -w "\n%{http_code}" "${GIT_API}")
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"
        [ "$http_code" != "200" ] && { echo "Error: Could not list remote files (HTTP $http_code)." >&2; exit 1; }
        paths=$(echo "$REPLY" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="name") print $(i+2)}' | grep '\.md$')
        echo "$paths" | while IFS= read -r path; do
            [ -z "$path" ] && continue
            echo "Syncing: $path"
            (cd "$NOTES_DIR" && pull_note "$path")
        done

    elif [ "$SYNC_ENGINE" = "DROPBOX" ]; then
        local resp http_code REPLY arg paths path
        arg=$(printf '{"path":"%s","recursive":true}' "$DROPBOX_PATH")
        resp=$(api_curl -w "\n%{http_code}" -X POST \
            -H "Content-Type: application/json" --data-binary "$arg" \
            "https://api.dropboxapi.com/2/files/list_folder")
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"
        [ "$http_code" != "200" ] && { echo "Error: Could not list remote files (HTTP $http_code)." >&2; exit 1; }
        paths=$(echo "$REPLY" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="path_display") print $(i+2)}' | grep '\.md$')
        echo "$paths" | while IFS= read -r path; do
            [ -z "$path" ] && continue
            rel_path=$(echo "$path" | sed "s|^$DROPBOX_PATH/||" | sed 's|^/||')
            echo "Syncing: $rel_path"
            dir=$(dirname "$rel_path")
            [ "$dir" != "." ] && mkdir -p "$NOTES_DIR/$dir"
            (cd "$NOTES_DIR" && pull_note "$rel_path")
        done

    else
        local base_encoded_path xml_response raw_paths path dec_path rel_path dir
        base_encoded_path=$(urlenc "$gn_PATH")
        xml_response=$(api_curl -X PROPFIND -H "Depth: 1" -H "Content-Type: text/xml" "${gn_URL}${base_encoded_path}")
        if [ -z "$xml_response" ]; then
            echo "Error: Could not retrieve remote file list." >&2; exit 1
        fi
        raw_paths=$(echo "$xml_response" | tr -d '\n\r' | sed -E 's/<\/[^>]*href>//g' | sed -E 's/<[^>]*href>/\n/g' | grep -v '^[[:space:]]*$')
        echo "$raw_paths" | while IFS= read -r path; do
            [ -z "$path" ] && continue
            dec_path=$(urldec "$path")
            case "$dec_path" in
                *"$gn_PATH"*.*.md)
                    rel_path=$(echo "$dec_path" | sed "s|.*$gn_PATH||" | sed 's|^/||')
                    echo "Syncing: $rel_path"
                    dir=$(dirname "$rel_path")
                    [ "$dir" != "." ] && mkdir -p "$NOTES_DIR/$dir"
                    (cd "$NOTES_DIR" && pull_note "$rel_path")
                    ;;
            esac
        done
    fi

    echo "Sync complete."
    exit 0
}

reconfigure() {
    rm -f "$CONFIG_FILE"
    echo "Saved config cleared. Run gn again to set up new credentials."
    exit 0
}

# --- Entry Point ---
if [ "$1" = "-r" ]; then
    [ -z "$2" ] || [ -z "$3" ] && { echo "Usage: gn -r OLD NEW"; exit 1; }
    rename_note "$2" "$3"
fi

ACTION_RUN=0
while getopts "htcd:s" opt; do
    case $opt in
        h) show_help ;;
        t) NOTE_NAME=$(date '+%Y-%m-%d') ;;
        c) ACTION_RUN=1; reconfigure ;;
        d) ACTION_RUN=1; delete_note "$OPTARG" ;;
        s) ACTION_RUN=1; sync_all_remote ;;
        *) show_help ;;
    esac
done
[ "$ACTION_RUN" -eq 1 ] && exit 0
shift $((OPTIND - 1))

[ -z "$NOTE_NAME" ] && NOTE_NAME="${1:-note}"
if [ "$NOTE_NAME" = "gn.conf" ] || [ "$NOTE_NAME" = "gn.sh" ]; then
    echo "Error: Cannot open runtime files via gn."
    exit 1
fi

case "$NOTE_NAME" in *.md) ;; *) NOTE_NAME="${NOTE_NAME}.md" ;; esac

cd "$NOTES_DIR" || { echo "Error: Cannot access $NOTES_DIR"; exit 1; }
[ "$(dirname "$NOTE_NAME")" != "." ] && mkdir -p "$(dirname "$NOTE_NAME")"

echo "Fetching... [$SYNC_ENGINE]"
pull_note "$NOTE_NAME"

PRE_SHA=$(get_file_hash "$NOTE_NAME")
$EDITOR "$NOTE_NAME"

[ -f "$NOTE_NAME" ] || { echo "Note not saved. Cancelled."; exit 0; }

POST_SHA=$(get_file_hash "$NOTE_NAME")
if [ "$PRE_SHA" = "$POST_SHA" ]; then
    echo "No changes. Sync skipped."
else
    echo "Pushing... [$SYNC_ENGINE]"
    push_note "$NOTE_NAME"
    echo "Done."
fi
