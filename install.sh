#!/usr/bin/env bash
set -e

echo "========================================="
echo "       Starting Setup: gn script         "
echo "========================================="

NOTES_DIR="$HOME/gn"
INSTALL_DIR="/usr/local/bin"

echo ""
echo "Select your sync backend:"
echo "  1) GitHub"
echo "  2) Dropbox"
read -rp "Enter choice [1-2]: " ENGINE_CHOICE

if [ "$ENGINE_CHOICE" = "1" ]; then
    # --- GitHub Provisioning Setup Flow ---
    echo ""
    echo "--- Configuring credentials for GitHub ---"
    echo ""

    TOKEN_URL="https://github.com/settings/tokens/new?scopes=repo&description=gn-cli"
    echo "You need a Personal Access Token with 'repo' scope."
    echo "Token generation page: $TOKEN_URL"
    echo ""
    read -rp "Open this page in your browser now? [Y/n]: " OPEN_BROWSER
    OPEN_BROWSER="${OPEN_BROWSER:-Y}"

    if [[ "$OPEN_BROWSER" =~ ^[Yy]$ ]]; then
        if command -v xdg-open &>/dev/null; then
            xdg-open "$TOKEN_URL" 2>/dev/null &
        elif command -v open &>/dev/null; then
            open "$TOKEN_URL" 2>/dev/null &
        else
            echo "(Could not open browser automatically — paste the URL above manually.)"
        fi
        echo "Waiting for you to generate your token..."
        echo ""
    fi

    # --- Credentials ---
    read -rp "Paste your Personal Access Token: " GIT_TOKEN
    echo ""
    read -rp "Account username: " GIT_OWNER
    echo ""
    read -rp "Repository name [gn]: " GIT_REPO
    GIT_REPO="${GIT_REPO:-gn}"
    echo ""

    # --- Token Validation ---
    echo "-> Validating token..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $GIT_TOKEN" \
        "https://api.github.com/user")

    if [ "$HTTP_CODE" != "200" ]; then
        echo ""
        echo "Error: Token validation failed (HTTP $HTTP_CODE)."
        echo "Check your token has the correct permissions and try again."
        exit 1
    fi
    echo "   Token valid."

    # --- Repo Check + Optional Creation ---
    echo "-> Checking repository '$GIT_REPO'..."
    REPO_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $GIT_TOKEN" \
        "https://api.github.com/repos/${GIT_OWNER}/${GIT_REPO}")

    if [ "$REPO_CODE" = "200" ]; then
        echo "   Repository '$GIT_REPO' found."
    else
        echo ""
        echo "   Repository '$GIT_REPO' not found on GitHub."
        read -rp "   Create it now as a private repository? [Y/n]: " CREATE_REPO
        CREATE_REPO="${CREATE_REPO:-Y}"

        if [[ "$CREATE_REPO" =~ ^[Yy]$ ]]; then
            echo "-> Creating private repository '$GIT_REPO'..."
            CREATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "Authorization: token $GIT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"$GIT_REPO\",\"private\":true,\"auto_init\":true}" \
                "https://api.github.com/user/repos")

            if [[ "$CREATE_CODE" =~ ^(200|201)$ ]]; then
                echo "   Repository '$GIT_REPO' created successfully."
            else
                echo ""
                echo "Error: Could not create repository (HTTP $CREATE_CODE)."
                echo "Create it manually on GitHub and re-run this installer."
                exit 1
            fi
        else
            echo ""
            echo "Create the repository manually on GitHub then re-run this installer."
            exit 0
        fi
    fi

    # --- Write Config ---
    echo ""
    echo "-> Creating directory structure at $NOTES_DIR..."
    mkdir -p "$NOTES_DIR"

    echo "-> Writing configuration file..."
    cat << CONF > "$NOTES_DIR/gn.conf"
# gn configuration (GitHub backend)
GIT_TOKEN=$GIT_TOKEN
GIT_OWNER=$GIT_OWNER
GIT_REPO=$GIT_REPO
CONF
    chmod 600 "$NOTES_DIR/gn.conf"
    echo "   Config saved: $NOTES_DIR/gn.conf"

elif [ "$ENGINE_CHOICE" = "2" ]; then
    # --- Dropbox Provisioning Setup Flow ---
    echo ""
    echo "Go to https://www.dropbox.com/developers/apps, build a scoped app folder entry"
    echo "ensuring 'files.content.write' and 'files.content.read' scopes are fully updated."
    echo ""
    read -rp "Paste your Dropbox App key: " DROPBOX_APP_KEY
    read -rp "Paste your Dropbox App secret: " DROPBOX_APP_SECRET

    if [ -z "$DROPBOX_APP_KEY" ] || [ -z "$DROPBOX_APP_SECRET" ]; then
        echo "Error: App credentials cannot be left blank." ; exit 1
    fi

    AUTH_URL="https://www.dropbox.com/oauth2/authorize?client_id=${DROPBOX_APP_KEY}&response_type=code&token_access_type=offline"
    echo -e "\nOpen link to authenticate: $AUTH_URL\n"
    read -rp "Paste confirmation authorization code: " AUTH_CODE

    echo "-> Exchanging credentials for OAuth persistence keys..."
    TOKEN_RESP=$(curl -s -X POST "https://api.dropbox.com/oauth2/token" \
        -d code="$AUTH_CODE" \
        -d grant_type=authorization_code \
        -d client_id="$DROPBOX_APP_KEY" \
        -d client_secret="$DROPBOX_APP_SECRET")

    DROPBOX_REFRESH_TOKEN=$(echo "$TOKEN_RESP" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="refresh_token") {print $(i+2); exit}}')
    DROPBOX_ACCESS_TOKEN=$(echo "$TOKEN_RESP" | awk -F'"' '{for(i=1;i<=NF;i++) if($i=="access_token") {print $(i+2); exit}}')

    if [ -z "$DROPBOX_REFRESH_TOKEN" ] || [ -z "$DROPBOX_ACCESS_TOKEN" ]; then
        echo "Error: Key provisioning failed. Response payload: $TOKEN_RESP" ; exit 1
    fi

    read -rp "Dropbox folder target destination [/notes]: " DROPBOX_PATH
    DROPBOX_PATH="${DROPBOX_PATH:-/notes}"
    DROPBOX_PATH="/${DROPBOX_PATH#/}"

    HDR=$(mktemp); chmod 600 "$HDR"
    echo "Authorization: Bearer $DROPBOX_ACCESS_TOKEN" > "$HDR"
    CREATE_ARG=$(printf '{"path":"%s"}' "$DROPBOX_PATH")
    curl -s -o /dev/null -X POST "https://api.dropboxapi.com/2/files/create_folder_v2" -H "@$HDR" -H "Content-Type: application/json" --data-binary "$CREATE_ARG"
    rm -f "$HDR"

    # --- Write Config ---
    echo ""
    echo "-> Creating directory structure at $NOTES_DIR..."
    mkdir -p "$NOTES_DIR"

    echo "-> Writing configuration file..."
    cat << CONF > "$NOTES_DIR/gn.conf"
# gn configuration (Dropbox backend)
DROPBOX_APP_KEY=$DROPBOX_APP_KEY
DROPBOX_APP_SECRET=$DROPBOX_APP_SECRET
DROPBOX_REFRESH_TOKEN=$DROPBOX_REFRESH_TOKEN
DROPBOX_PATH=$DROPBOX_PATH
CONF
    chmod 600 "$NOTES_DIR/gn.conf"
    echo "   Config saved: $NOTES_DIR/gn.conf"

else
    echo "Error: Invalid selection made." ; exit 1
fi

# --- Fetch and Install Executable ---
echo ""
echo "-> Downloading gn.sh from production source..."
if curl -s -f -o "$NOTES_DIR/gn.sh" "https://gn-notes.pages.dev/gn.sh"; then
    chmod +x "$NOTES_DIR/gn.sh"
    echo "   Saved and made executable: $NOTES_DIR/gn.sh"

    echo "-> Deploying system binary to $INSTALL_DIR/gn (requires sudo)..."
    sudo cp "$NOTES_DIR/gn.sh" "$INSTALL_DIR/gn"
    echo "   Binary installed successfully."
else
    echo "Error: Failed to download gn.sh from https://gn-notes.pages.dev/gn.sh"
    exit 1
fi

echo ""
echo "========================================="
echo "             Setup complete!             "
echo " Run 'gn' to open your first note."
echo "========================================="
