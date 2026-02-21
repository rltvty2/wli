#!/usr/bin/env bash
# run_installer.sh – launch the Linux Live Installer with root privileges

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$SCRIPT_DIR/ulli_v09014.py"

if [[ ! -f "$INSTALLER" ]]; then
    echo "Error: ulli_v09014.py not found in $SCRIPT_DIR"
    exit 1
fi

# Quick dependency check
python3 "$INSTALLER" --check-deps

echo ""
echo "Launching installer (requires root)..."
if command -v pkexec &>/dev/null; then
    pkexec env DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" \
        python3 "$INSTALLER"
else
    sudo -E python3 "$INSTALLER"
fi
