#!/usr/bin/env bash
# wazuh-installer.sh
# Installs Wazuh (server + indexer + dashboard) on Ubuntu and validates services.
# Tested for Ubuntu 24.04.3
# Created by H.A

set -euo pipefail

WAZUH_VERSION="4.14"
INSTALLER_URL="https://packages.wazuh.com/${WAZUH_VERSION}/wazuh-install.sh"
GPG_KEY_URL="https://packages.wazuh.com/key/GPG-KEY-WAZUH"
WAZUH_LIST="/etc/apt/sources.list.d/wazuh.list"
WAZUH_GPG="/etc/apt/trusted.gpg.d/wazuh.gpg"
INSTALLER="wazuh-install.sh"

log() { printf "\n\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\n\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\n\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run this script with sudo or as root."
    exit 1
  fi
}

check_ubuntu() {
  if ! grep -qi ubuntu /etc/os-release; then
    warn "This does not look like Ubuntu. Continuing anyway..."
  fi
}

update_packages() {
  log "Updating Ubuntu packages (apt update)…"
  apt update
}

install_libs() {
  log "Installing required libraries/tools…"
  apt install -y vim curl apt-transport-https gnupg2 software-properties-common lsb-release unzip wget libcap2-bin
}

add_repo_gpg() {
  if [[ -f "$WAZUH_GPG" ]]; then
    log "Wazuh GPG key already present: $WAZUH_GPG"
  else
    log "Adding Wazuh repository GPG key…"
    curl -fsSL "$GPG_KEY_URL" | gpg --dearmor | tee "$WAZUH_GPG" >/dev/null
  fi
}

add_repo() {
  if [[ -f "$WAZUH_LIST" ]] && grep -q "packages.wazuh.com" "$WAZUH_LIST"; then
    log "Wazuh APT repository already configured: $WAZUH_LIST"
  else
    log "Adding Wazuh APT repository…"
    echo "deb [signed-by=${WAZUH_GPG}] https://packages.wazuh.com/4.x/apt/ stable main" | tee "$WAZUH_LIST" >/dev/null
  fi
  log "Updating package lists after adding repo…"
  apt update
}

get_installer() {
  log "Downloading Wazuh installer ${WAZUH_VERSION}…"
  rm -f "$INSTALLER"
  curl -fsSL -L -o "$INSTALLER" "$INSTALLER_URL"
}

verify_installer_head() {
  log "Verifying installer header (first 3 lines)…"
  head -n 3 "$INSTALLER" || true
  local first_line
  first_line="$(head -n 1 "$INSTALLER" || true)"
  if [[ "$first_line" != "#!"* ]]; then
    err "Installer does not look like a shell script (first line: '$first_line'). Aborting."
    exit 2
  fi
}

make_executable() {
  log "Making installer executable…"
  chmod +x "$INSTALLER"
}

run_installer() {
  log "Launching installer in automatic mode (-a)…"
  bash "./$INSTALLER" -a
}

enable_services() {
  log "Enabling and starting services (if needed)…"
  systemctl daemon-reload || true

  for svc in wazuh-manager wazuh-indexer wazuh-dashboard; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
      systemctl enable --now "$svc"
    else
      warn "Service $svc not found (may be renamed or not installed yet)."
    fi
  done
}

check_status() {
  log "Checking Wazuh services status…"
  systemctl status wazuh-manager wazuh-indexer wazuh-dashboard --no-pager || true
}

test_filebeat() {
  if command -v filebeat >/dev/null 2>&1; then
    log "Testing Filebeat output…"
    filebeat test output || true
  else
    warn "Filebeat not found; skipping 'filebeat test output'."
  fi
}

main() {
  require_root
  check_ubuntu
  update_packages
  install_libs
  add_repo_gpg
  add_repo
  update_packages
  get_installer
  verify_installer_head
  make_executable
  run_installer
  enable_services
  check_status
  test_filebeat
  log "All done. If the dashboard isn't reachable yet, check indexer logs: /var/log/wazuh-indexer/wazuh-indexer.log"
}

main "$@"
