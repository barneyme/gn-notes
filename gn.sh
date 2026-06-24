#!/usr/bin/env bash
# gn - Get Notes
# A zero-dependency CLI tool to sync markdown notes via GitHub or WebDAV.
# Web: gn.tuxs.me. Author: Barney Matthews. License: MIT

NOTES_DIR="$HOME/gn"
CONFIG_FILE="$NOTES_DIR/gn.conf"

mkdir -p "$NOTES_DIR"

for cmd in curl grep sed awk tr; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' is required but not installed." >&2; exit 1; }
done

# --- Security & Resource Cleanup Trap ---
cleanup() {
    rm -f "$nf" "$hdr" "$pfile" "$file.tmp" 2>/dev/null
}
trap cleanup EXIT INT TERM HUP

# --- Config ---
if [ -f "$CONFIG_FILE" ]; then
    chmod 600 "$CONFIG_FILE"
    while IFS='=' read -r key value; do
        key=$(echo "$key" | tr -d ' ')
        [[ -z "$key" || "$key" =~ ^# ]] && continue

        value="${value%%#*}"
        value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [[ "$value" =~ ^[\'\"](.*)[\'\"]$ ]] && value="${BASH_REMATCH[1]}"
        case "$key" in
            gn_USER)               gn_USER="$value" ;;
            gn_PASS)               gn_PASS="$value" ;;
            gn_PATH)               gn_PATH="$value" ;;
            gn_URL)                gn_URL="$value" ;;
            GIT_TOKEN)             GIT_TOKEN="$value" ;;
            GIT_OWNER)             GIT_OWNER="$value" ;;
            GIT_REPO)              GIT_REPO="$value" ;;
            GIT_API)               GIT_API="$value" ;;
        esac
    done < "$CONFIG_FILE"
fi

# --- Interactive First-Run Setup Wizard ---
if [ -z "$gn_USER" ] && [ -z "$GIT_TOKEN" ]; then
    echo "No config found at $CONFIG_FILE - let's set one up."
    echo "Select your provider:"
    echo "1) GitHub"
    echo "2) Nextcloud"
    echo "3) Koofr"
    echo "4) WebDAV (generic)"
    printf "Choice [1-4]: "
    read -r provider_choice

    case "$provider_choice" in
        1)
            printf "GitHub Personal Access Token (input hidden): "
            stty -echo; read -r GIT_TOKEN; stty echo; echo
            printf "GitHub username (repo owner): "
            read -r GIT_OWNER
            printf "Repository name: "
            read -r GIT_REPO
            ;;
        2)
            printf "Nextcloud instance URL (e.g., https://cloud.example.com): "
            read -r nc_host
            nc_host="${nc_host%/}"
            printf "Nextcloud username: "
            read -r gn_USER
            gn_URL="${nc_host}/remote.php/dav/files/${gn_USER}"
            printf "Nextcloud app password (input hidden): "
            stty -echo; read -r gn_PASS; stty echo; echo
            printf "Remote notes folder [/gn]: "
            read -r gn_PATH
            gn_PATH="${gn_PATH:-/gn}"
            ;;
        3)
            gn_URL="https://app.koofr.net/dav/Koofr"
            printf "Koofr email/username: "
            read -r gn_USER
            printf "Koofr app password (input hidden): "
            stty -echo; read -r gn_PASS; stty echo; echo
            printf "Remote notes folder [/gn]: "
            read -r gn_PATH
            gn_PATH="${gn_PATH:-/gn}"
            ;;
        *)
            printf "WebDAV base URL (e.g., https://dav.example.com/remote.php/dav/files/user): "
            read -r gn_URL
            gn_URL="${gn_URL%/}"
            printf "WebDAV username: "
            read -r gn_USER
            printf "WebDAV password (input hidden): "
            stty -echo; read -r gn_PASS; stty echo; echo
            printf "Remote notes folder [/gn]: "
            read -r gn_PATH
            gn_PATH="${gn_PATH:-/gn}"
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
elif [ -n "$gn_USER" ] && [ -n "$gn_PASS" ] && [ -n "$gn_URL" ]; then
    if [[ "$gn_URL" =~ koofr\.net ]]; then
        SYNC_ENGINE="KOOFR"
    else
        SYNC_ENGINE="WEBDAV"
    fi
    gn_URL="${gn_URL%/}"
    gn_PATH="${gn_PATH:-/notes}"
    gn_PATH="/${gn_PATH#/}"
    [ "$gn_PATH" = "//" ] && gn_PATH="/"
else
    echo "Error: gn.conf is incomplete. Provide GitHub or WebDAV credentials." >&2
    exit 1
fi

EDITOR="${EDITOR:-nano}"

show_help() {
    local remote_info
    case "$SYNC_ENGINE" in
        GITHUB)  remote_info="GitHub: ${GIT_OWNER}/${GIT_REPO}" ;;
        KOOFR)   remote_info="Koofr: ${gn_URL}${gn_PATH}" ;;
        WEBDAV)  remote_info="WebDAV: ${gn_URL}${gn_PATH}" ;;
    esac
    cat <<EOF
Usage: gn [options] [note]

  -h          Show this help
  -d NOTE     Delete a note (local + remote)
  -r OLD NEW  Rename a note (local + remote)
  -s          Sync (pull) all remote notes down to local directory
  -c          Clear saved credentials and reconfigure

Local commands:
  ls -lt $NOTES_DIR/*.md                        List notes, newest first
  grep -ril "term" $NOTES_DIR/                  Search notes (filenames only)
  grep -rn "term" $NOTES_DIR/                   Search notes (matching lines)
  cp -r $NOTES_DIR $NOTES_DIR-$(date +%Y%m%d)   Backup notes directory with date stamp

Engine: $SYNC_ENGINE
Remote: $remote_info
Local:  $NOTES_DIR
EOF
    exit 0
}

api_curl() {
    local hdr rc
    if [ "$SYNC_ENGINE" = "KOOFR" ] || [ "$SYNC_ENGINE" = "WEBDAV" ]; then
        local host
        host=$(echo "$gn_URL" | awk -F/ '{print $3}')
        nf=$(mktemp); chmod 600 "$nf"
        printf 'machine %s\nlogin %s\npassword %s\n' "$host" "$gn_USER" "$gn_PASS" > "$nf"
        curl -s --netrc-file "$nf" "$@"; rc=$?
        rm -f "$nf"; return $rc
    else
        hdr=$(mktemp); chmod 600 "$hdr"
        printf 'header = "Authorization: Bearer %s"\n' "$GIT_TOKEN" > "$hdr"
        curl -s -K "$hdr" "$@"; rc=$?
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
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum "$1" 2>/dev/null | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        if md5 -q "$1" >/dev/null 2>&1; then
            md5 -q "$1" 2>/dev/null
        else
            md5 "$1" 2>/dev/null | awk '{print $NF}'
        fi
    else
        ls -ln "$1" 2>/dev/null | awk '{print $5,$6,$7,$8}'
    fi
}

# --- Pure POSIX Engines for Base64 and JSON ---

# Bulletproof line/string parser instead of regular expression record splitting
posix_parse_json() {
    local target_key="$1"
    awk -v target="$target_key" '
    {
        idx = index($0, "\"" target "\"");
        if (idx > 0) {
            str = substr($0, idx + length(target) + 2);
            col = index(str, ":");
            if (col > 0) {
                str = substr(str, col + 1);
                q1 = index(str, "\"");
                if (q1 > 0) {
                    str = substr(str, q1 + 1);
                    q2 = index(str, "\"");
                    if (q2 > 0) {
                        print substr(str, 1, q2 - 1);
                        exit;
                    }
                }
            }
        }
    }
    '
}

posix_b64encode() {
    awk '
    BEGIN {
        split("A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 + /", b64, " ");
        for(i=0; i<256; i++) { c=sprintf("%c", i); chrmap[c]=i }
        ORS=""; BINMODE=1;
        nbytes=0;
    }
    {
        line = $0;
        n = length(line);
        for(i=1; i<=n; i++) bytes[nbytes++] = chrmap[substr(line,i,1)];
        bytes[nbytes++] = 10;
    }
    END {
        if (nbytes > 0 && bytes[nbytes-1] == 10) nbytes--;
        for(i=0; i<nbytes; i+=3) {
            c1 = bytes[i];
            c2 = (i+1 < nbytes) ? bytes[i+1] : 0;
            c3 = (i+2 < nbytes) ? bytes[i+2] : 0;
            print b64[1 + int(c1/4)];
            print b64[1 + (and_posix(c1,3)*16 + int(c2/16))];
            if (i+1 < nbytes) print b64[1 + (and_posix(c2,15)*4 + int(c3/64))];
            else print "=";
            if (i+2 < nbytes) print b64[1 + and_posix(c3,63)];
            else print "=";
        }
    }
    function and_posix(a, b,    r, bit) {
        r=0; bit=1;
        while(a>0 && b>0) {
            if (a%2==1 && b%2==1) r+=bit;
            a=int(a/2); b=int(b/2); bit*=2;
        }
        return r;
    }
    '
}

posix_b64decode() {
    awk '
    BEGIN {
        str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        for(i=1; i<=64; i++) alphabet[substr(str, i, 1)] = i - 1;
        ORS=""; BINMODE=1;
    }
    {
        gsub(/[^A-Za-z0-9\+\/=]/, "");
        len = length($0);
        for(i=1; i<=len; i+=4) {
            s1 = substr($0, i, 1);
            s2 = substr($0, i+1, 1);
            if (s1 == "" || s2 == "") continue;

            b1 = alphabet[s1];
            b2 = alphabet[s2];
            b3 = substr($0, i+2, 1);
            b4 = substr($0, i+3, 1);

            c1 = lshift_posix(b1, 2) + int(b2 / 16);
            printf "%c", c1;

            if (b3 != "=" && b3 != "") {
                v3 = alphabet[b3];
                c2 = lshift_posix(and_posix(b2, 15), 4) + int(v3 / 4);
                printf "%c", c2;

                if (b4 != "=" && b4 != "") {
                    v4 = alphabet[b4];
                    c3 = lshift_posix(and_posix(v3, 3), 6) + v4;
                    printf "%c", c3;
                }
            }
        }
    }
    function and_posix(a, b,    local_res, bit) {
        local_res = 0; bit = 1;
        while(a > 0 && b > 0) {
            if (a % 2 == 1 && b % 2 == 1) local_res += bit;
            a = int(a / 2); b = int(b / 2); bit *= 2;
        }
        return local_res;
    }
    function lshift_posix(v, n) { while(n-- > 0) v *= 2; return v; }
    '
}

remote_url() { echo "${gn_URL}$(urlenc "${gn_PATH}/$1")"; }

remote_mkdir() {
    local dir="$1" path="" part parts target
    if [ -z "$dir" ] || [ "$dir" = "." ]; then target="$gn_PATH"; else target="$gn_PATH/$dir"; fi
    IFS='/' read -ra parts <<< "$target"
    for part in "${parts[@]}"; do
        [ -z "$part" ] && continue
        path="$path/$part"
        [ "$SYNC_ENGINE" = "KOOFR" ] || [ "$SYNC_ENGINE" = "WEBDAV" ] && api_curl -X MKCOL "${gn_URL}$(urlenc "$path")" -o /dev/null
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
        [ "$http_code" != "200" ] && { echo "Error: Pull failed (HTTP $http_code)" >&2; exit 1; }

        content=$(echo "$REPLY" | posix_parse_json "content" | tr -d '\n\r ')

        if [ -n "$content" ] && [ "$content" != "null" ]; then
            echo "$content" | posix_b64decode > "$file"
        fi
    else
        local url http_code
        url=$(remote_url "$file")
        http_code=$(api_curl -w "%{http_code}" -o "$file.tmp" "$url")
        case "$http_code" in
            200) mv "$file.tmp" "$file" ;;
            404) rm -f "$file.tmp" "$file" ;;
            429)
                rm -f "$file.tmp"
                echo "Rate limited by server (HTTP 429), retrying in 5s..." >&2
                sleep 5
                http_code=$(api_curl -w "%{http_code}" -o "$file.tmp" "$url")
                case "$http_code" in
                    200) mv "$file.tmp" "$file" ;;
                    404) rm -f "$file.tmp" "$file" ;;
                    *)   rm -f "$file.tmp"; echo "Error: Pull failed after retry (HTTP $http_code) url=$url" >&2; exit 1 ;;
                esac
                ;;
            *)   rm -f "$file.tmp"; echo "Error: Pull failed (HTTP $http_code) url=$url" >&2; exit 1 ;;
        esac
    fi
}

push_note() {
    local file="$1"
    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        local url sha sha_resp http_code content msg pfile REPLY safe_msg safe_file
        msg="gn: update $file $(date '+%Y-%m-%d %H:%M:%S')"
        safe_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
        safe_file=$(printf '%s' "$file" | sed 's/\\/\\\\/g; s/"/\\"/g')
        url="${GIT_API}/${safe_file}"

        content=$(posix_b64encode < "$file")

        pfile=$(mktemp); chmod 600 "$pfile"
        sha_resp=$(api_curl -s "$url")

        sha=$(echo "$sha_resp" | grep -o '"sha"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/"sha"[[:space:]]*:[[:space:]]*"//;s/"$//')

        if [ -n "$sha" ] && [ "$sha" != "null" ]; then
            printf '%s' "{\"message\":\"${safe_msg}\",\"content\":\"${content}\",\"sha\":\"${sha}\"}" > "$pfile"
        else
            printf '%s' "{\"message\":\"${safe_msg}\",\"content\":\"${content}\"}" > "$pfile"
        fi
        resp=$(api_curl -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" --data-binary "@$pfile" "$url")
        rm -f "$pfile"
        http_code="${resp##*$'\n'}"
        REPLY="${resp%$'\n'*}"
        [[ "$http_code" =~ ^(200|201)$ ]] || { echo "Error: Push failed (HTTP $http_code)" >&2; exit 1; }
    else
        local url http_code dir
        dir=$(dirname "$file")
        remote_mkdir "$dir"
        url=$(remote_url "$file")
        http_code=$(api_curl -w "%{http_code}" -o /dev/null -X PUT --data-binary "@$file" "$url")
        case "$http_code" in
            200|201|204) ;;
            *) echo "Error: Push failed (HTTP $http_code) url=$url" >&2; exit 1 ;;
        esac
    fi
}

remote_delete() {
    local file="$1" msg="${2:-gn: delete $1}"
    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        local url sha sha_resp http_code resp pfile
        url="${GIT_API}/$file"
        pfile=$(mktemp); chmod 600 "$pfile"
        sha_resp=$(api_curl -s "$url")

        sha=$(echo "$sha_resp" | grep -o '"sha"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/"sha"[[:space:]]*:[[:space:]]*"//;s/"$//')

        if [ -z "$sha" ] || [ "$sha" = "null" ]; then rm -f "$pfile"; return 0; fi
        printf '{"message":"%s","sha":"%s"}' "$msg" "$sha" > "$pfile"
        resp=$(api_curl -w "\n%{http_code}" -X PUT -H "Content-Type: application/json" --data-binary "@$pfile" "$url")
        rm -f "$pfile"
    else
        local url; url=$(remote_url "$file")
        api_curl -s -X DELETE "$url" > /dev/null
    fi
}

remote_rename() {
    local old="$1" new="$2"
    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        cp "$old" "$new"
        push_note "$new"
        remote_delete "$old" "gn: rename $old to $new"
        rm -f "$new"
    else
        local src dst; src=$(remote_url "$old"); dst=$(remote_url "$new")
        remote_mkdir "$(dirname "$new")"
        api_curl -s -X MOVE -H "Destination: $dst" -H "Overwrite: F" "$src" > /dev/null
    fi
}

delete_note() {
    local file="$1"
    case "$file" in *.md) ;; *) file="${file}.md" ;; esac
    [ -f "$file" ] || { echo "Error: '$file' not found."; exit 1; }
    printf "Delete '%s'? [y/N] " "$file"
    read -r confirm
    case "$confirm" in [Yy]*) ;; *) echo "Aborted."; exit 0 ;; esac
    remote_delete "$file"
    rm "$file"
    echo "Deleted."
    exit 0
}

rename_note() {
    local old="$1" new="$2"
    case "$old" in *.md) ;; *) old="${old}.md" ;; esac
    case "$new" in *.md) ;; *) new="${new}.md" ;; esac
    [ -f "$old" ] || { echo "Error: '$old' not found."; exit 1; }
    remote_rename "$old" "$new"
    mkdir -p "$(dirname "$new")" 2>/dev/null
    mv "$old" "$new"
    echo "Renamed."
    exit 0
}

sync_all_remote() {
    echo "Syncing paths... [$SYNC_ENGINE]"
    if [ "$SYNC_ENGINE" = "GITHUB" ]; then
        local resp
        resp=$(api_curl -s "${GIT_API}")

        echo "$resp" | awk '
        BEGIN { RS="[{},]" }
        /\"name\":/ {
            gsub(/.*\"name\":\"|\"/, "");
            if ($0 ~ /\.md$/) print $0;
        }' | while read -r path; do
            [ -n "$path" ] && pull_note "$path"
        done
    else
        local base_encoded_path xml_response
        base_encoded_path=$(urlenc "$gn_PATH")
        xml_response=$(api_curl -X PROPFIND -H "Depth: infinity" -H "Content-Type: text/xml" "${gn_URL}${base_encoded_path}")
        echo "$xml_response" | grep -oE '<[A-Za-z:]*href>[^<]+' | sed -E 's|<[^>]+>||g' | while read -r path; do
            local dec_path; dec_path=$(urldec "$path")
            if [[ "$dec_path" =~ .*"$gn_PATH"/(.*\.md)$ ]]; then
                local rel_path="${BASH_REMATCH[1]}"
                mkdir -p "$(dirname "$rel_path")" 2>/dev/null
                pull_note "$rel_path"
            fi
        done
    fi
    echo "Sync complete."
    exit 0
}

reconfigure() { rm -f "$CONFIG_FILE"; echo "Config cleared."; exit 0; }

# --- Execution Entry ---
cd "$NOTES_DIR" || exit 1

if [ "$1" = "-r" ]; then rename_note "$2" "$3"; fi
ACTION_RUN=0
while getopts "hcd:s" opt; do
    case $opt in
        h) show_help ;;
        c) ACTION_RUN=1; reconfigure ;;
        d) ACTION_RUN=1; delete_note "$OPTARG" ;;
        s) ACTION_RUN=1; sync_all_remote ;;
        *) show_help ;;
    esac
done
[ "$ACTION_RUN" -eq 1 ] && exit 0
shift $((OPTIND - 1))

NOTE_NAME="${1:-note}"
if [[ "$NOTE_NAME" == *..* ]] || [ "$NOTE_NAME" = "gn.conf" ]; then exit 1; fi
case "$NOTE_NAME" in *.md) ;; *) NOTE_NAME="${NOTE_NAME}.md" ;; esac

mkdir -p "$(dirname "$NOTE_NAME")" 2>/dev/null

pull_note "$NOTE_NAME"
PRE_SHA=$(get_file_hash "$NOTE_NAME")
$EDITOR "$NOTE_NAME"

[ -f "$NOTE_NAME" ] || exit 0
POST_SHA=$(get_file_hash "$NOTE_NAME")
if [ "$PRE_SHA" != "$POST_SHA" ]; then
    push_note "$NOTE_NAME"
fi
