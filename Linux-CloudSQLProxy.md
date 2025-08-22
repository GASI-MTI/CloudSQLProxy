
# Explicação Técnica — Script `cloudsql-proxy.sh`

O script `cloudsql-proxy.sh` foi desenvolvido para **automatizar o processo de autenticação no Google Cloud Platform (GCP)**, configurar o **acesso ao GKE** e iniciar o **Cloud SQL Proxy** para conectar em instâncias do Cloud SQL usando **login humano**.

---

## Objetivo

O objetivo é simplificar o fluxo que, normalmente, exigiria rodar manualmente vários comandos como:

```bash
gcloud auth login
gcloud config set project <PROJECT_ID>
gcloud container clusters get-credentials <CLUSTER_NAME> --region <REGION>
~/.cloudsql-proxy/cloud-sql-proxy <CONNECTION_NAME> --gcloud-auth
````

O script **reúne tudo isso** em uma execução única, além de:

* Validar se as dependências estão instaladas.
* Explicar a função de cada componente antes de instalar.
* Perguntar se o usuário deseja instalar automaticamente pacotes faltantes.
* Oferecer um menu para selecionar a instância Cloud SQL.

---

## Estrutura do Script

### 1. Variáveis fixas

```bash
PROJETO_GCP="plataformagovdigital-gcp-main"
CLUSTER_NAME="cluster-prod-plataformagovdigital"
CLUSTER_REGION="southamerica-east1"
PROXY_VERSION="v2.16.0"
PROXY_DIR="$HOME/.cloudsql-proxy"
PROXY_FILE="$PROXY_DIR/cloud-sql-proxy"
```

* Define o projeto padrão, cluster, região e versão do Proxy.
* O binário do Proxy fica em `~/.cloudsql-proxy/cloud-sql-proxy`.

---

### 2. Funções de utilidade

* **msg()** → imprime mensagens coloridas no terminal (`INFO`, `SUCCESS`, `WARNING`, `ERROR`).
* **confirm()** → função para perguntar ao usuário se deseja instalar algo.
* **need\_sudo()** → garante uso de `sudo` apenas quando necessário.

---

### 3. Validação de Dependências

* **curl** → usado para baixar binários.
* **gcloud** → CLI oficial do Google.
* **gke-gcloud-auth-plugin** → plugin de autenticação para `kubectl` falar com GKE.
* **kubectl** → cliente Kubernetes.
* **Cloud SQL Proxy** → binário que cria o túnel local para instâncias do Cloud SQL.

Se faltar algo:

* O script **explica para que serve**.
* Pergunta se deseja instalar via `apt-get` ou `curl`.
* Só instala se o usuário confirmar.

---

### 4. Autenticação no GCP

Executa:

```bash
gcloud auth login
gcloud config set project $PROJETO_GCP
```

* Faz login humano no navegador.
* Define o projeto padrão `plataformagovdigital-gcp-main`.

---

### 5. Configuração do GKE

Executa:

```bash
gcloud container clusters get-credentials $CLUSTER_NAME \
  --region $CLUSTER_REGION \
  --project $PROJETO_GCP
```

* Baixa credenciais do cluster GKE.
* Atualiza `~/.kube/config` para que `kubectl` funcione.

---

### 6. Escolha da instância Cloud SQL

O script lista todas as instâncias do projeto:

```bash
gcloud sql instances list \
  --project $PROJETO_GCP \
  --format="value(NAME,DATABASE_VERSION)"
```

Exemplo:

```
1) xvia-ss-postgres (POSTGRES_12)
2) cluster-postgresql-dev (POSTGRES_14)
3) cluster-postgresql-mtlogin-prod (POSTGRES_16)
```

O usuário escolhe o número, e o script monta automaticamente o **Connection Name**:

```
plataformagovdigital-gcp-main:southamerica-east1:cluster-postgresql-dev
```

---

### 7. Execução do Cloud SQL Proxy

Por fim, o script inicia o Proxy:

```bash
$PROXY_FILE $INSTANCIA_GCP --gcloud-auth
```

* Abre o túnel em `localhost:5432`.
* Permite conectar no banco como se estivesse local.
* Fica rodando até o usuário encerrar com **Ctrl+C**.

---

## Resumo do Fluxo

1. Verifica dependências e instala se autorizado.
2. Faz login humano no GCP.
3. Define o projeto fixo.
4. Configura cluster GKE.
5. Lista instâncias Cloud SQL → você escolhe.
6. Inicia o Proxy apontando para `localhost:5432`.

---

## Conexão no Banco

Depois que o Proxy está rodando:

### Terminal (psql)

```bash
psql "host=127.0.0.1 port=5432 dbname=SEU_DB user=SEU_USER password=SEU_PASSWORD"
```

### pgAdmin

* Host: `127.0.0.1`
* Port: `5432`
* Database: `SEU_DB`
* Username: `SEU_USER`
* Password: `SUA_SENHA`

### DBeaver

* Host: `127.0.0.1`
* Port: `5432`
* Database: `SEU_DB`
* Username: `SEU_USER`
* Password: `SUA_SENHA`

---

## Encerrar o Proxy

Basta usar **Ctrl + C** no terminal onde ele está rodando.

```

---
