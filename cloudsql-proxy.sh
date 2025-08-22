#!/usr/bin/env bash
#===========================================================
# Autor:      George Rodrigues de Oliveira
# Licença:    MIT
# Versão:     4.0
# Data:       2025-08-22
# Descrição:  GCP login + validação de componentes + GKE + Cloud SQL Proxy
#             Projeto/região fixos e escolha interativa da instância.
#===========================================================

set -euo pipefail

# ------------------------
# Parâmetros fixos (ajuste aqui se precisar)
# ------------------------
PROJETO_GCP="plataformagovdigital-gcp-main"
CLUSTER_NAME="cluster-prod-plataformagovdigital"
CLUSTER_REGION="southamerica-east1"
PROXY_VERSION="v2.16.0"
PROXY_DIR="$HOME/.cloudsql-proxy"
PROXY_FILE="$PROXY_DIR/cloud-sql-proxy"

# ------------------------
# Utilitários de mensagem
# ------------------------
msg() {
  local type="$1"; shift
  case "$type" in
    INFO)    echo -e "\033[36m[INFO]\033[0m $*";;
    SUCCESS) echo -e "\033[32m[SUCCESS]\033[0m $*";;
    WARNING) echo -e "\033[33m[WARNING]\033[0m $*";;
    ERROR)   echo -e "\033[31m[ERROR]\033[0m $*";;
  esac
}

confirm() {
  # uso: confirm "pergunta" && comando
  local prompt="$1"
  read -r -p "$prompt [Y/n]: " ans || true
  [[ -z "${ans:-}" || "$ans" =~ ^[Yy]$ ]]
}

need_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "sudo"
  else
    echo ""
  fi
}

# ------------------------
# Validações/instalações
# ------------------------
ensure_curl() {
  if command -v curl >/dev/null 2>&1; then
    msg SUCCESS "curl OK"
  else
    msg WARNING "curl é necessário para baixar binários e repositórios."
    if confirm "Instalar curl via apt agora?"; then
      $(need_sudo) apt-get update
      $(need_sudo) apt-get install -y curl
      msg SUCCESS "curl instalado"
    else
      msg ERROR "curl é obrigatório. Abortando."
      exit 1
    fi
  fi
}

ensure_gcloud_repo() {
  # adiciona o repositório oficial do Google (se necessário)
  if [[ ! -f /etc/apt/sources.list.d/google-cloud-cli.list ]]; then
    msg INFO "Configurando repositório do Google Cloud CLI (APT)..."
    $(need_sudo) apt-get update
    $(need_sudo) apt-get install -y apt-transport-https ca-certificates gnupg
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
      $(need_sudo) gpg --dearmor -o /usr/share/keyrings/google-cloud.gpg
    echo "deb [signed-by=/usr/share/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
      $(need_sudo) tee /etc/apt/sources.list.d/google-cloud-cli.list >/dev/null
    $(need_sudo) apt-get update
  fi
}

ensure_gcloud() {
  if command -v gcloud >/dev/null 2>&1; then
    msg SUCCESS "gcloud (Google Cloud CLI) OK"
  else
    msg WARNING "gcloud é necessário para autenticar, configurar projeto, GKE e Cloud SQL."
    msg INFO "Ele permite: 'gcloud auth login', 'gcloud container clusters get-credentials', 'gcloud sql ...'."
    if confirm "Instalar gcloud via APT agora?"; then
      ensure_curl
      ensure_gcloud_repo
      $(need_sudo) apt-get install -y google-cloud-cli
      msg SUCCESS "gcloud instalado"
    else
      msg ERROR "gcloud é obrigatório. Abortando."
      exit 1
    fi
  fi
}

ensure_gke_auth_plugin() {
  if command -v gke-gcloud-auth-plugin >/dev/null 2>&1; then
    msg SUCCESS "gke-gcloud-auth-plugin OK"
  else
    msg WARNING "O plugin 'gke-gcloud-auth-plugin' é necessário para o kubectl autenticar no GKE."
    msg INFO "Sem ele, 'kubectl' falhará ao falar com o cluster (erro CRITICAL)."
    if confirm "Instalar plugin e kubectl via APT agora?"; then
      ensure_gcloud_repo
      $(need_sudo) apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin kubectl
      msg SUCCESS "gke-gcloud-auth-plugin e kubectl instalados"
    else
      msg WARNING "Tentando instalar via 'gcloud components' (pode não existir em instalações APT)."
      if gcloud components install gke-gcloud-auth-plugin --quiet; then
        msg SUCCESS "Plugin instalado via gcloud components"
      else
        msg ERROR "Não foi possível instalar o plugin. Instale via APT ou habilite o repositório do Google."
        exit 1
      fi
    fi
  fi
  export USE_GKE_GCLOUD_AUTH_PLUGIN=True
}

ensure_proxy() {
  mkdir -p "$PROXY_DIR"
  if [[ -x "$PROXY_FILE" ]]; then
    msg SUCCESS "Cloud SQL Proxy já existe - $PROXY_FILE"
    "$PROXY_FILE" --version || true
    return
  fi
  msg WARNING "Cloud SQL Proxy é necessário para expor sua instância Cloud SQL localmente (localhost:5432)."
  if confirm "Baixar e instalar Cloud SQL Proxy $PROXY_VERSION agora?"; then
    local os="linux"
    local arch="$(uname -m)"
    case "$arch" in
      x86_64) arch="amd64" ;;
      aarch64|arm64) arch="arm64" ;;
      *) msg ERROR "Arquitetura não suportada: $arch"; exit 1 ;;
    esac
    local url="https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/$PROXY_VERSION/cloud-sql-proxy.$os.$arch"
    msg INFO "Baixando Cloud SQL Proxy de $url"
    curl -sSL "$url" -o "$PROXY_FILE"
    chmod +x "$PROXY_FILE"
    msg SUCCESS "Cloud SQL Proxy instalado"
    "$PROXY_FILE" --version
  else
    msg ERROR "Sem Cloud SQL Proxy não é possível criar o túnel local para o banco. Abortando."
    exit 1
  fi
}

# ------------------------
# Fluxo GCP/GKE/Proxy
# ------------------------
auth_gcloud() {
  msg INFO "Autenticando usuário humano no GCP..."
  gcloud auth login
  gcloud config set project "$PROJETO_GCP"
  msg SUCCESS "Login concluído e projeto definido: $PROJETO_GCP"
}

configure_gke() {
  msg INFO "Obtendo credenciais do cluster GKE $CLUSTER_NAME na região $CLUSTER_REGION..."
  gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --region "$CLUSTER_REGION" \
    --project "$PROJETO_GCP"
  msg SUCCESS "Cluster configurado no kubectl"
}

choose_instance() {
  msg INFO "Buscando instâncias Cloud SQL em $PROJETO_GCP..."
  instances=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && instances+=("$line")
  done < <(gcloud sql instances list --project "$PROJETO_GCP" --format="value(NAME,DATABASE_VERSION)")

  if [[ ${#instances[@]} -eq 0 ]]; then
    msg ERROR "Nenhuma instância Cloud SQL encontrada no projeto $PROJETO_GCP"
    exit 1
  fi

  echo ""
  echo "Selecione a instância Cloud SQL:"
  local i=1
  for inst in "${instances[@]}"; do
    local name dbv
    name="$(echo "$inst" | awk '{print $1}')"
    dbv="$(echo "$inst"  | awk '{print $2}')"
    echo "  $i) $name ($dbv)"
    i=$((i+1))
  done

  printf "Digite o número da instância desejada: "
  read choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#instances[@]} )); then
    msg ERROR "Opção inválida"; exit 1
  fi

  INSTANCE_NAME="$(echo "${instances[$((choice-1))]}" | awk '{print $1}')"
  INSTANCIA_GCP="$PROJETO_GCP:$CLUSTER_REGION:$INSTANCE_NAME"
  msg SUCCESS "Instância escolhida: $INSTANCIA_GCP"
}

start_proxy() {
  msg INFO "Iniciando Cloud SQL Proxy para instância: $INSTANCIA_GCP"
  msg INFO "Porta padrão: 5432 (PostgreSQL)"
  msg WARNING "Pressione Ctrl+C para encerrar"
  "$PROXY_FILE" "$INSTANCIA_GCP" --gcloud-auth
}

# ------------------------
# Execução principal
# ------------------------
ensure_curl
ensure_gcloud
ensure_gke_auth_plugin
auth_gcloud
configure_gke
ensure_proxy
choose_instance
start_proxy
