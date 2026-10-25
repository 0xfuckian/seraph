#!/usr/bin/env bash
# ==============================================================================
# Seraph Protocol — Automated BookStack Installation Script for Ubuntu LTS
# Reference: https://www.bookstackapp.com/docs/admin/installation/
# ==============================================================================

set -euo pipefail

echo "======================================================================"
echo "  Seraph Protocol — Official BookStack Installation Script            "
echo "  Target: Ubuntu 22.04 / 24.04 LTS Bare-Metal or Cloud VPS            "
echo "======================================================================"

if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] This script must be run as root. Run with sudo: sudo ./install-ubuntu.sh"
   exit 1
fi

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  read -rp "Enter the domain or IP for BookStack (e.g., docs.seraphprotocol.tech or localhost): " DOMAIN
fi

if [[ -z "$DOMAIN" ]]; then
  echo "[ERROR] Domain or IP address is required."
  exit 1
fi

# Detect Ubuntu Version
UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "22.04")
echo "[1/4] Detected Ubuntu version: ${UBUNTU_VER}"

SCRIPT_URL="https://raw.githubusercontent.com/BookStackApp/devops/main/scripts/installation-ubuntu-${UBUNTU_VER}.sh"

# Fallback to 22.04 script if specific version not found
if ! curl --output /dev/null --silent --head --fail "$SCRIPT_URL"; then
  echo "[WARN] Exact script for ${UBUNTU_VER} not found. Defaulting to 22.04 LTS script..."
  SCRIPT_URL="https://raw.githubusercontent.com/BookStackApp/devops/main/scripts/installation-ubuntu-22.04.sh"
fi

echo "[2/4] Downloading official BookStack installation script from BookStackApp/devops..."
TMP_SCRIPT=$(mktemp)
curl -sSL "$SCRIPT_URL" -o "$TMP_SCRIPT"
chmod +x "$TMP_SCRIPT"

echo "[3/4] Running BookStack setup for domain: ${DOMAIN}..."
"$TMP_SCRIPT" "$DOMAIN"

rm -f "$TMP_SCRIPT"

echo "======================================================================"
echo "  BookStack Installation Finished Successfully!                       "
echo "======================================================================"
echo "Access your instance at: http://${DOMAIN}"
echo "Default Administrator Credentials:"
echo "  Username / Email: admin@admin.com"
echo "  Password:         password"
echo ""
echo "[ACTION REQUIRED]:"
echo "1. Log in immediately and change the admin password."
echo "2. Go to User Profile -> API Tokens to generate your Token ID and Secret."
echo "3. Run the automated documentation seeder to populate all 22 chapters:"
echo "   npm run sync --prefix deploy/bookstack"
echo "======================================================================"
