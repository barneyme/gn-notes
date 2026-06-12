#!/usr/bin/env bash
set -e

echo "========================================="
echo "       Starting Setup: gn script         "
echo "========================================="

NOTES_DIR="$HOME/gn"
INSTALL_DIR="/usr/local/bin"

# --- Provider Selection ---
echo ""
echo "Select your Git platform provider:"
echo "1) GitHub (github.com)"
echo "2) GitLab (gitlab.com)"
echo "3) Codeberg (codeberg.org)"
read -rp "Enter choice [1-3, default 1]: " PROV_IDX
PROV_IDX="${PROV_IDX:-1}"

case "$PROV_IDX" in
    2) GIT_PROVIDER="gitlab" ;;
    3) GIT_PROVIDER="codeberg" ;;
    *) GIT_PROVIDER="github" ;;
esac

# --- Token URL + guidance ---
echo ""
echo "--- Configuring credentials for $GIT_PROVIDER ---"
echo ""

case "$GIT_PROVIDER" in
    github)
        TOKEN_URL="https://github.com/settings/tokens/new?scopes=repo&description=gn-cli"
        echo "You need a Personal Access Token with 'repo' scope."
        ;;
    gitlab)
        TOKEN_URL="https://gitlab.com/-/user_settings/personal_access_tokens?scopes=api&name=gn-cli"
        echo "You need a Personal Access Token with 'api' scope."
        ;;
    codeberg)
        TOKEN_URL="https://codeberg.org/user/settings/applications"
        echo "You need an Access Token with repository read/write permissions."
        ;;
esac

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

case "$GIT_PROVIDER" in
    github)
        VALIDATE_URL="https://api.github.com/user"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: token $GIT_TOKEN" \
            "$VALIDATE_URL")
        ;;
    gitlab)
        VALIDATE_URL="https://gitlab.com/api/v4/user"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "PRIVATE-TOKEN: $GIT_TOKEN" \
            "$VALIDATE_URL")
        ;;
    codeberg)
        VALIDATE_URL="https://codeberg.org/api/v1/user"
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: token $GIT_TOKEN" \
            "$VALIDATE_URL")
        ;;
esac

if [ "$HTTP_CODE" != "200" ]; then
    echo ""
    echo "Error: Token validation failed (HTTP $HTTP_CODE)."
    echo "Check your token has the correct permissions and try again."
    exit 1
fi
echo "   Token valid."

# --- Repo Check + Optional Creation ---
echo "-> Checking repository '$GIT_REPO'..."

case "$GIT_PROVIDER" in
    github)
        REPO_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: token $GIT_TOKEN" \
            "https://api.github.com/repos/${GIT_OWNER}/${GIT_REPO}")
        ;;
    gitlab)
        ENCODED="${GIT_OWNER}%2F${GIT_REPO}"
        REPO_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "PRIVATE-TOKEN: $GIT_TOKEN" \
            "https://gitlab.com/api/v4/projects/${ENCODED}")
        ;;
    codeberg)
        REPO_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: token $GIT_TOKEN" \
            "https://codeberg.org/api/v1/repos/${GIT_OWNER}/${GIT_REPO}")
        ;;
esac

if [ "$REPO_CODE" = "200" ]; then
    echo "   Repository '$GIT_REPO' found."
else
    echo ""
    echo "   Repository '$GIT_REPO' not found on $GIT_PROVIDER."
    read -rp "   Create it now as a private repository? [Y/n]: " CREATE_REPO
    CREATE_REPO="${CREATE_REPO:-Y}"

    if [[ "$CREATE_REPO" =~ ^[Yy]$ ]]; then
        echo "-> Creating private repository '$GIT_REPO'..."

        case "$GIT_PROVIDER" in
            github)
                CREATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                    -X POST \
                    -H "Authorization: token $GIT_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "{\"name\":\"$GIT_REPO\",\"private\":true,\"auto_init\":true}" \
                    "https://api.github.com/user/repos")
                ;;
            gitlab)
                CREATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                    -X POST \
                    -H "PRIVATE-TOKEN: $GIT_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "{\"name\":\"$GIT_REPO\",\"visibility\":\"private\",\"initialize_with_readme\":true}" \
                    "https://gitlab.com/api/v4/projects")
                ;;
            codeberg)
                CREATE_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                    -X POST \
                    -H "Authorization: token $GIT_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "{\"name\":\"$GIT_REPO\",\"private\":true,\"auto_init\":true}" \
                    "https://codeberg.org/api/v1/user/repos")
                ;;
        esac

        if [[ "$CREATE_CODE" =~ ^(200|201)$ ]]; then
            echo "   Repository '$GIT_REPO' created successfully."
        else
            echo ""
            echo "Error: Could not create repository (HTTP $CREATE_CODE)."
            echo "Create it manually on $GIT_PROVIDER and re-run this installer."
            exit 1
        fi
    else
        echo ""
        echo "Create the repository manually on $GIT_PROVIDER then re-run this installer."
        exit 0
    fi
fi

# --- Write Config ---
echo ""
echo "-> Creating directory structure at $NOTES_DIR..."
mkdir -p "$NOTES_DIR"

echo "-> Writing configuration file..."
cat << CONF > "$NOTES_DIR/gn.conf"
# gn configuration
GIT_PROVIDER=$GIT_PROVIDER
GIT_TOKEN=$GIT_TOKEN
GIT_OWNER=$GIT_OWNER
GIT_REPO=$GIT_REPO
CONF
chmod 600 "$NOTES_DIR/gn.conf"
echo "   Config saved: $NOTES_DIR/gn.conf"

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
