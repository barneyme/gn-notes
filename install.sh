#!/usr/bin/env bash
set -e

echo "========================================="
echo "       Starting Setup: gn script         "
echo "========================================="

NOTES_DIR="$HOME/gn"
INSTALL_DIR="/usr/local/bin"

echo ""
read -rp "GitHub Personal Access Token: " GH_TOKEN
read -rp "GitHub Username:              " GH_OWNER
read -rp "GitHub Repository Name [gn]:  " GH_REPO
GH_REPO="${GH_REPO:-gn}"
echo ""

echo "-> Creating directory structure at $NOTES_DIR..."
mkdir -p "$NOTES_DIR"

echo "-> Writing configuration..."
cat << CONF > "$NOTES_DIR/gn.conf"
# Configuration rules for gn command line tool
GH_TOKEN="$GH_TOKEN"
GH_OWNER="$GH_OWNER"
GH_REPO="$GH_REPO"
CONF
chmod 600 "$NOTES_DIR/gn.conf"
echo "   Saved: $NOTES_DIR/gn.conf"

# Guard safety rails to prevent local dev overwriting
if [ -f "$NOTES_DIR/gn.sh" ]; then
    echo "-> Warning: A local script copy already exists at $NOTES_DIR/gn.sh"
    read -rp "   Do you want to overwrite it with the remote production build? [y/N] " overwrite
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
        echo "-> Downloading production gn.sh..."
        curl -fsSL "https://gn-notes.pages.dev/gn.sh" -o "$NOTES_DIR/gn.sh"
    else
        echo "   Skipped downloading gn.sh to preserve local shifts."
    fi
else
    echo "-> Downloading gn.sh..."
    curl -fsSL "https://gn-notes.pages.dev/gn.sh" -o "$NOTES_DIR/gn.sh"
fi

chmod +x "$NOTES_DIR/gn.sh"
echo "   Ready: $NOTES_DIR/gn.sh"

echo "-> Installing binary target executable..."
if [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; then
    cp "$NOTES_DIR/gn.sh" "$INSTALL_DIR/gn"
else
    sudo cp "$NOTES_DIR/gn.sh" "$INSTALL_DIR/gn"
fi
echo "   Installed: $INSTALL_DIR/gn"

echo "========================================="
echo "Complete! Run 'gn' from your shell."
echo "========================================="
