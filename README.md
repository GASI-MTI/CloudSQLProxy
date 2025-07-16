Com certeza! Aqui está o **README** revisado, já incluindo a seção detalhada de conexão ao banco de dados após o start do proxy.

---

# CloudSQLProxy.ps1

## Visão Geral

Este script PowerShell automatiza o download, instalação e execução do **Cloud SQL Proxy** no Windows, permitindo conexões seguras a bancos PostgreSQL no Google Cloud Platform (**GCP**) com autenticação humana.
Ideal para equipes de desenvolvimento, suporte e operações que precisam conectar localmente ao banco Cloud SQL.

---

## Pré-requisitos

* **Windows 10/11** com PowerShell 5.1 ou superior
* Permissão de administrador para instalar programas
* Conta Google Cloud com acesso à instância desejada
* Conexão estável com a internet

---

## Como Usar

### 1. Download e Salvamento

* Baixe o arquivo `CloudSQLProxy.ps1` e salve em uma pasta fácil, como **Documentos** ou **Downloads**.

### 2. Abrir o PowerShell como Administrador

* Clique em **Iniciar**, procure por `PowerShell`, clique com o direito e escolha **Executar como administrador**.

### 3. Permitir Execução de Scripts

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

### 4. Acesse a Pasta Onde o Script Foi Salvo

```powershell
cd $env:USERPROFILE\Documents
```

*ou*

```powershell
cd $env:USERPROFILE\Downloads
```

### 5. Execute o Script

```powershell
.\CloudSQLProxy.ps1
```

### 6. Autentique-se

* Siga a instrução do terminal para fazer login com sua conta Google autorizada no projeto.

---

## 7. Conectar ao Banco de Dados Usando o Cloud SQL Auth Proxy

Após iniciar o proxy, ele criará uma conexão local.
Use as informações abaixo para conectar-se ao banco de dados usando **pgAdmin**, **psql**, **DBeaver** ou qualquer outro cliente PostgreSQL:

| Parâmetro | Valor                                 |
| --------- | ------------------------------------- |
| Host      | 127.0.0.1                             |
| Porta     | 5432                                  |
| Username  | (Usuário configurado no Cloud SQL)    |
| Password  | (Senha correspondente ao usuário)     |
| Database  | (Nome do banco de dados no Cloud SQL) |

* **Observação:** O usuário, a senha e o nome do banco são exatamente os cadastrados/configurados na instância Cloud SQL.

* O proxy estará ativo enquanto a janela do PowerShell estiver aberta.

* **Para encerrar:** Pressione `Ctrl + C` no PowerShell e depois feche a janela.

---

## Alternando entre DEV e PROD

O parâmetro `$InstanciaGCP` define qual banco Cloud SQL será acessado:

```powershell
[string]$InstanciaGCP = "plataformagovdigital-gcp-main:southamerica-east1:cluster-postgresql-dev",
# [string]$InstanciaGCP = "plataformagovdigital-gcp-main:southamerica-east1:cluster-postgresql",
```

* **Para acessar o ambiente de produção (PROD):**

  * **Comente** a linha do DEV (adicione `#` no início).
  * **Descomente** a linha do PROD (remova `#` do início).

---

## Parâmetros Opcionais

| Nome                | Descrição                                           | Exemplo                                |
| ------------------- | --------------------------------------------------- | -------------------------------------- |
| `ProjetoGCP`        | Nome do projeto no GCP                              | `"meu-projeto"`                        |
| `InstanciaGCP`      | Instância do Cloud SQL (projeto\:regiao\:instancia) | `"meu-projeto:regiao:minha-instancia"` |
| `ProxyVersion`      | Versão do Cloud SQL Proxy                           | `"v2.16.0"`                            |
| `ProxyDir`          | Pasta de instalação do proxy                        | `"C:\CloudSQL"`                        |
| `SkipGCloudInstall` | Pula instalação do Google Cloud SDK                 | `-SkipGCloudInstall`                   |

---

## Resolução de Problemas

* **Erro de permissão:** Execute sempre como administrador.
* **Não abriu o navegador para login:** Rode manualmente `gcloud auth login` e tente de novo.
* **Sem internet:** O script exige conexão para baixar dependências.
* **Porta 5432 ocupada:** Finalize outros processos que usam essa porta ou altere a porta conforme sua necessidade.

---

## Recursos

* [Documentação oficial Cloud SQL Proxy](https://cloud.google.com/sql/docs/postgres/connect-admin-proxy)
* [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)

---

## Segurança

* Não compartilhe suas credenciais.
* Use apenas contas autorizadas no projeto.

---

Se precisar de exemplos de conexão, prints ou suporte, consulte a documentação interna ou fale com o responsável DevOps.

---

Se quiser o README em inglês ou adaptado para outro cenário, só avisar!
