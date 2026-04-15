#!/bin/bash
#
# VDSok Install — bootstrap script
# Downloads and launches vdsok-install on the rescue system
#

set -e

INSTALL_DIR="/opt/vdsok-install"
REPO_URL="https://github.com/Kefisto/vdsok-install.git"

echo -e "\033[1;36m"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║         VDSok Install Bootstrap        ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "\033[0m"

if command -v git &>/dev/null; then
  echo "[*] Cloning vdsok-install..."
  if [ -d "$INSTALL_DIR" ]; then
    echo "[*] Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull --ff-only 2>/dev/null || {
      echo "[*] Clean re-clone..."
      cd /
      rm -rf "$INSTALL_DIR"
      git clone "$REPO_URL" "$INSTALL_DIR"
    }
  else
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
else
  echo "[*] Git not found, downloading archive..."
  mkdir -p "$INSTALL_DIR"
  curl -sSL "https://github.com/Kefisto/vdsok-install/archive/refs/heads/master.tar.gz" | \
    tar xz -C "$INSTALL_DIR" --strip-components=1
fi

chmod +x "$INSTALL_DIR/vdsok-install"
chmod +x "$INSTALL_DIR/vdsok-install.in_screen"

echo ""
echo -e "\033[1;32m[OK] VDSok Install downloaded to $INSTALL_DIR\033[0m"
echo ""
echo "  Run interactively:   $INSTALL_DIR/vdsok-install"
echo "  Run in screen:       $INSTALL_DIR/vdsok-install.in_screen"
echo "  Auto mode example:   $INSTALL_DIR/vdsok-install -a -i /path/to/image -n hostname"
echo ""
echo "  Configs available in: $INSTALL_DIR/configs/"
echo ""

exec "$INSTALL_DIR/vdsok-install" "$@"
