#!/bin/bash
# Script: install-xvia-local.sh
# Author: georgeroliveira | Version: 1.8 | Date: 2025-07-05 | License: MIT
# Description: Local installation of X-Road Security Server (FI) with dependencies, cache and temporary directory.

set -euo pipefail

# Detecta se está sendo executado fora de bash (ex: sudo sh script.sh)
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "[ERRO] Este script requer bash. Use: sudo bash $0"
  exit 1
fi

trap 'echo -e "\033[1;31m[ERRO]\033[0m Falha na linha $LINENO. Abortando." >&2; exit 1' ERR
# === GLOBAL VARIABLES ===
SCRIPT_VERSION="1.8"
SCRIPT_DATE="2025-07-05"
SCRIPT_DESC="Automated local installation of X-Road Security Server"
PACKAGE_ARCHIVE="xvia-ubuntu22.7-6-1-update-v3.tar.gz"
PACKAGE_URL="https://storage.googleapis.com/artifacts.xvia-main.appspot.com/xvia-releases/$PACKAGE_ARCHIVE"
CACHE_DIR="/var/cache/xvia"
TEMP_DIR=$(mktemp -d -t xvia-temp-XXXX)
CONFIG_FILE="/etc/xroad.properties"
LOG_FILE="/var/log/xroad-install.log"
ADMIN_USERNAME=""

# === LOGGING ===
log() {
  local level="$1"; shift
  local msg="$*"
  local color=""
  case "$level" in
    INFO) color="\033[1;34m";;
    OK) color="\033[1;32m";;
    WARN) color="\033[1;33m";;
    ERROR) color="\033[1;31m";;
    *) color="";;
  esac
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${color}[$level]\033[0m $msg" | tee -a "$LOG_FILE"
}

# === CLEANUP ===
cleanup() {
  [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# === USER SETUP ===
define_admin_user() {
  while true; do
    read -p "Enter the administrator username (DO NOT use 'xroad'): " input
    if [[ "$input" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] && [[ "$input" != "xroad" ]]; then
      ADMIN_USERNAME="$input"
      break
    else
      log ERROR "Invalid or reserved username. Please try again."
    fi
  done
}

criar_usuario_admin() {
    while true; do
        read -p "Digite o nome do usuário administrador (NÃO use 'xroad'): " ADMIN_USERNAME_INPUT
        if [[ "$ADMIN_USERNAME_INPUT" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] && [[ "$ADMIN_USERNAME_INPUT" != "xroad" ]]; then
            ADMIN_USERNAME="$ADMIN_USERNAME_INPUT"
            export ADMIN_USERNAME
            break
        else
            log ERRO "Nome de usuário inválido ou reservado. Tente novamente."
        fi
    done

    if id "$ADMIN_USERNAME" &>/dev/null; then
        log OK "Usuário '$ADMIN_USERNAME' já existe."
        read -p "Deseja definir uma nova senha para '$ADMIN_USERNAME'? (s/N): " resp
        resp=${resp,,}
        if [[ "$resp" =~ ^(s|sim|y|yes)$ ]]; then
            while true; do
                read -s -p "Digite a nova senha para '$ADMIN_USERNAME': " senha
                echo
                read -s -p "Confirme a nova senha: " senha_conf
                echo
                if [[ "$senha" == "$senha_conf" ]] && [[ -n "$senha" ]]; then
                    echo "$ADMIN_USERNAME:$senha" | sudo chpasswd
                    unset senha senha_conf
                    log OK "Senha atualizada para o usuário '$ADMIN_USERNAME'."
                    break
                else
                    log ERRO "Senhas não coincidem ou estão em branco. Tente novamente."
                fi
            done
        else
            log INFO "Mantendo senha atual do usuário '$ADMIN_USERNAME'."
        fi
    else
        log INFO "Criando usuário '$ADMIN_USERNAME'..."
        sudo adduser --gecos "" --disabled-password "$ADMIN_USERNAME"
        while true; do
            read -s -p "Digite a senha para '$ADMIN_USERNAME': " senha
            echo
            read -s -p "Confirme a senha: " senha_conf
            echo
            if [[ "$senha" == "$senha_conf" ]] && [[ -n "$senha" ]]; then
                echo "$ADMIN_USERNAME:$senha" | sudo chpasswd
                unset senha senha_conf
                log OK "Usuário '$ADMIN_USERNAME' criado com senha definida."
                break
            else
                log ERRO "Senhas não coincidem ou estão em branco. Tente novamente."
            fi
        done
    fi

    # Persistência local
    echo "$ADMIN_USERNAME" > "$HOME/.xroad_admin_user"
    chmod 600 "$HOME/.xroad_admin_user"
    log INFO "Usuário '$ADMIN_USERNAME' salvo em ~/.xroad_admin_user para referência futura."
}
# === SYSTEM CONFIGURATION ===
install_dependencies() {
  log INFO "Installing required packages..."
  sudo apt-get update
  sudo apt-get install -y curl tar sudo adduser dpkg locales software-properties-common \
    dialog ca-certificates gnupg2 rsyslog openjdk-21-jre-headless rlwrap ca-certificates-java crudini postgresql postgresql-contrib
}

configure_locale() {
  log INFO "Setting locale..."
  echo "LC_ALL=en_US.UTF-8" | sudo tee -a /etc/environment
  sudo locale-gen en_US.UTF-8
  sudo update-locale LC_ALL=en_US.UTF-8
  log OK "Locale configured."
}

# === PACKAGE INSTALLATION ===
download_and_extract_packages() {
  log INFO "Checking cache for package..."
  sudo mkdir -p "$CACHE_DIR"
  local cache_file="$CACHE_DIR/$PACKAGE_ARCHIVE"

  if [[ ! -f "$cache_file" ]]; then
    log INFO "Downloading from $PACKAGE_URL..."
    curl -fSL "$PACKAGE_URL" -o "$cache_file"
    log OK "Download completed."
  else
    log OK "Package found in cache: $cache_file"
  fi

  cp "$cache_file" "$TEMP_DIR/"
  local marker="$TEMP_DIR/xroad-base_7.6.1-1.ubuntu22.04_amd64.deb"
  if [[ ! -f "$marker" ]]; then
    tar -xzf "$TEMP_DIR/$PACKAGE_ARCHIVE" -C "$TEMP_DIR"
    log OK "Package extracted."
  else
    log OK "Package already extracted. Skipping."
  fi
}

install_packages() {
  local packages=($@)
  for pkg in "${packages[@]}"; do
    local path="$TEMP_DIR/$pkg"
    if [[ -f "$path" ]]; then
      log INFO "Installing $pkg..."
      sudo dpkg -i "$path" || sudo apt-get -f install -y
    else
      log ERROR "Package not found: $pkg"
      exit 1
    fi
  done
}

# === X-ROAD CONFIGURATION ===
configure_override_securityserver() {
  local conf_dir="/etc/xroad/conf.d"
  local conf_file="$conf_dir/override-securityserver-fi.ini"
  sudo mkdir -p "$conf_dir"
  sudo tee "$conf_file" > /dev/null <<'EOF'
; FI security server configuration overrides

[signer]
key-length=3072
enforce-token-pin-policy=true
csr-signature-digest-algorithm=SHA-256

[proxy]
client-tls-protocols=TLSv1.2,TLSv1.3
client-tls-ciphers=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_DHE_RSA_WITH_AES_128_GCM_SHA256,TLS_DHE_RSA_WITH_AES_128_CBC_SHA256,TLS_DHE_RSA_WITH_AES_256_CBC_SHA256,TLS_DHE_RSA_WITH_AES_256_GCM_SHA384
server-connector-max-idle-time=120000
server-support-clients-pooled-connections=true
pool-enable-connection-reuse=true
client-use-fastest-connecting-ssl-socket-autoclose=true
client-use-idle-connection-monitor=true
client-timeout=30000
server-min-supported-client-version=7.5.0

[proxy-ui-api]
acme-challenge-port-enabled=false

[message-log]
message-body-logging=false
acceptable-timestamp-failure-period=172800
EOF
  sudo chown xroad:xroad "$conf_file"
  sudo chmod 640 "$conf_file"
  log OK "Security server override configuration applied."
}

restart_services() {
  log INFO "Restarting X-Road services..."
  sudo systemctl daemon-reload
  sudo systemctl restart xroad-base xroad-signer xroad-proxy xroad-confclient \
    xroad-monitor xroad-addon-messagelog xroad-proxy-ui-api
}

check_services() {
  log INFO "Checking service statuses..."
  for svc in xroad-base xroad-signer xroad-proxy xroad-confclient xroad-monitor xroad-addon-messagelog xroad-proxy-ui-api; do
    if systemctl is-active --quiet "$svc"; then
      log OK "Service $svc is running."
    else
      log WARN "Service $svc is inactive. Starting..."
      sudo systemctl start "$svc"
    fi
  done
  sudo systemctl list-units "xroad*"
}

adjust_permissions() {
  log INFO "Adjusting permissions..."
  sudo chown -R xroad:xroad /etc/xroad/backup.d/00_xroad-confclient || true
  sudo chown -R xroad:xroad /etc/xroad/backup.d/10_xroad-signer || true
  log OK "Permissions set."
}

# === MAIN EXECUTION ===
main() {
  log INFO "Starting X-Road local installation..."
  criar_usuario_admin
  install_dependencies
  configure_locale
  download_and_extract_packages

  local pre_deps=(
    "xroad-base_7.6.1-1.ubuntu22.04_amd64.deb"
    "xroad-database-remote_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-confclient_7.6.1-1.ubuntu22.04_amd64.deb"
    "xroad-signer_7.6.1-1.ubuntu22.04_amd64.deb"
  )

  local main_deps=(
    "xroad-proxy_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-proxy-ui-api_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-addon-messagelog_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-addon-metaservices_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-monitor_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-opmonitor_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-addon-proxymonitor_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-addon-wsdlvalidator_7.6.1-1.ubuntu22.04_all.deb"
    "xroad-securityserver_7.6.1-1.ubuntu22.04_all.deb"
  )

  install_packages "${pre_deps[@]}"
  install_packages "${main_deps[@]}"
  configure_override_securityserver
  restart_services
  check_services
  adjust_permissions

  log OK "X-Road installation complete. Access via: https://<YOUR_IP_OR_DNS>:4000/"
}

main "$@"
