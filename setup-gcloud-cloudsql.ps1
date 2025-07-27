#Requires -Version 5.1

<#
===========================================================
 Autor:      George Rodrigues de Oliveira
 GitHub:     https://github.com/georgeroliveira
 Licença:    MIT
 Versão:     1.0
 Data:       2025-07-27
 Descrição:  Conexão ao Cloud SQL com autenticação humana
===========================================================
#>

<#
.SYNOPSIS
    Script para conectar ao Cloud SQL via Proxy em Windows com login de usuário humano.

.DESCRIPTION
    Instala/atualiza Google Cloud SDK e Cloud SQL Proxy, força login de usuário humano
    somente se necessário, e conecta à instância PostgreSQL do Google Cloud Platform.

.EXAMPLE
    .\CloudSQLProxy.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ProjetoGCP = "meu-projeto-gcp",

    [Parameter(Mandatory = $false)]
    [string]$InstanciaGCP = "meu-projeto-gcp:regiao:cluster-bd-dev",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$ProxyVersion = "v2.16.0",

    [Parameter(Mandatory = $false)]
    [string]$ProxyDir = (Join-Path $env:USERPROFILE "Documents"),

    [Parameter(Mandatory = $false)]
    [switch]$SkipGCloudInstall
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch {}

$Config = @{
    ProxyFileName = "cloud-sql-proxy.exe"
    ProxyTempName = "cloud-sql-proxy.x64.exe"
    ProxyBaseUrl = "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy"
    GCloudInstallerUrl = "https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe"
    MaxRetries = 3
    RetryDelaySeconds = 5
}

$Paths = @{
    ProxyFinal = Join-Path $ProxyDir $Config.ProxyFileName
    ProxyTemp = Join-Path $ProxyDir $Config.ProxyTempName
    ProxyUrl = "$($Config.ProxyBaseUrl)/$ProxyVersion/$($Config.ProxyTempName)"
    GCloudInstaller = Join-Path $env:TEMP "GoogleCloudSDKInstaller.exe"
}

function Write-ColoredMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][ValidateSet("Info", "Success", "Warning", "Error")][string]$Type = "Info"
    )
    $colorMap = @{ Info = "Cyan"; Success = "Green"; Warning = "Yellow"; Error = "Red" }
    $prefix = "[$($Type.ToUpper())]"
    Write-Host "$prefix $Message" -ForegroundColor $colorMap[$Type]
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    try { $null = Get-Command $CommandName -ErrorAction Stop; return $true }
    catch { return $false }
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $false)][int]$MaxRetries = $Config.MaxRetries,
        [Parameter(Mandatory = $false)][int]$DelaySeconds = $Config.RetryDelaySeconds,
        [Parameter(Mandatory = $false)][string]$ActionDescription = "Operação"
    )
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-ColoredMessage "Tentativa $i de $MaxRetries - $ActionDescription" -Type Info
            & $ScriptBlock
            return
        } catch {
            Write-ColoredMessage "Tentativa $i falhou - $($_.Exception.Message)" -Type Warning
            if ($i -eq $MaxRetries) {
                Write-ColoredMessage "Todas as tentativas falharam para - $ActionDescription" -Type Error
                throw $_
            }
            Write-ColoredMessage "Aguardando $DelaySeconds segundos antes da próxima tentativa..." -Type Info
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Install-GCloudSDK {
    if (Test-CommandExists "gcloud") {
        Write-ColoredMessage "Google Cloud SDK já está instalado" -Type Success
        return
    }
    if ($SkipGCloudInstall) {
        Write-ColoredMessage "Instalação do gcloud foi pulada conforme solicitado" -Type Warning
        throw "Google Cloud SDK não encontrado e instalação foi pulada"
    }
    Write-ColoredMessage "Google Cloud SDK não encontrado. Iniciando instalação..." -Type Info
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Config.GCloudInstallerUrl -OutFile $Paths.GCloudInstaller -UseBasicParsing -ErrorAction Stop
        $process = Start-Process -FilePath $Paths.GCloudInstaller -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "Instalador falhou com código de saída - $($process.ExitCode)"
        }
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    } catch {
        Write-ColoredMessage "Erro ao instalar Google Cloud SDK - $($_.Exception.Message)" -Type Error
        throw
    } finally {
        if (Test-Path $Paths.GCloudInstaller) {
            try { Remove-Item $Paths.GCloudInstaller -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Install-CloudSQLProxy {
    if (Test-Path $Paths.ProxyFinal) {
        try {
            $versionOutput = & $Paths.ProxyFinal --version 2>&1
            Write-ColoredMessage "Cloud SQL Proxy já existe e está funcional - $($Paths.ProxyFinal)" -Type Success
            Write-ColoredMessage "Versão instalada - $versionOutput" -Type Info
            return
        } catch {
            Write-ColoredMessage "Proxy existe mas não é executável. Fazendo re-download..." -Type Warning
            try { Remove-Item $Paths.ProxyFinal -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    Write-ColoredMessage "Instalando Cloud SQL Proxy versão $ProxyVersion..." -Type Info
    try {
        if (-not (Test-Path $ProxyDir)) {
            New-Item -Path $ProxyDir -ItemType Directory -Force | Out-Null
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "PowerShell CloudSQL Script")
        try {
            $webClient.DownloadFile($Paths.ProxyUrl, $Paths.ProxyTemp)
        } finally { $webClient.Dispose() }
        if (-not (Test-Path $Paths.ProxyTemp)) { throw "Falha no download do proxy" }
        $fileInfo = Get-Item $Paths.ProxyTemp
        if ($fileInfo.Length -eq 0) { throw "Arquivo baixado está vazio" }
        Move-Item -Path $Paths.ProxyTemp -Destination $Paths.ProxyFinal -Force
        $versionOutput = & $Paths.ProxyFinal --version 2>&1
        Write-ColoredMessage "Cloud SQL Proxy instalado com sucesso - $($Paths.ProxyFinal)" -Type Success
        Write-ColoredMessage "Versão - $versionOutput" -Type Info
    } catch {
        Write-ColoredMessage "Erro ao instalar Cloud SQL Proxy - $($_.Exception.Message)" -Type Error
        @($Paths.ProxyTemp, $Paths.ProxyFinal) | ForEach-Object {
            if (Test-Path $_) { try { Remove-Item $_ -Force -ErrorAction SilentlyContinue } catch {} }
        }
        throw
    }
}

function Ensure-HumanAuth {
    $activeUser = & gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
    if (-not $activeUser -or $activeUser -match "compute@developer\\.gserviceaccount\\.com") {
        Write-ColoredMessage "Login necessário! Será aberto o navegador para autenticação Google." -Type Warning
        Write-ColoredMessage "Use uma conta humana do GCP com permissão no projeto: $ProjetoGCP" -Type Info
        Read-Host "Pressione Enter para abrir o navegador e fazer login"
        & gcloud auth login
        $activeUser = & gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
        if (-not $activeUser -or $activeUser -match "compute@developer\\.gserviceaccount\\.com") {
            Write-ColoredMessage "A conta ativa ainda não é humana! Repita o login." -Type Error
            throw "Conta inválida ou sem permissão."
        }
        Write-ColoredMessage "Conta autenticada: $activeUser" -Type Success
    } else {
        Write-ColoredMessage "Conta ativa: $activeUser" -Type Success
    }
}

function Initialize-GCloudProject {
    Write-ColoredMessage "Definindo projeto GCP - $ProjetoGCP" -Type Info
    & gcloud config set project $ProjetoGCP
    Write-ColoredMessage "Projeto GCP definido" -Type Success
}

function Start-CloudSQLProxy {
    Write-ColoredMessage "Iniciando Cloud SQL Proxy para instância - $InstanciaGCP" -Type Info
    Write-ColoredMessage "Proxy executável - $($Paths.ProxyFinal)" -Type Info
    Write-ColoredMessage "Porta padrão - 5432 (PostgreSQL)" -Type Info
    Write-ColoredMessage "Pressione Ctrl+C para interromper o proxy" -Type Warning
    & $Paths.ProxyFinal $InstanciaGCP --gcloud-auth
}

function Test-Prerequisites {
    Write-ColoredMessage "Verificando pré-requisitos..." -Type Info
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell 5.1 ou superior é necessário. Versão atual - $($PSVersionTable.PSVersion)"
    }
    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
        throw "Este script foi desenvolvido para Windows. SO atual - $($PSVersionTable.Platform)"
    }
    try {
        $null = Invoke-WebRequest -Uri "https://google.com" -UseBasicParsing -TimeoutSec 5
    } catch {
        throw "Sem conectividade com a internet. Verifique sua conexão."
    }
    Write-ColoredMessage "Pré-requisitos verificados com sucesso" -Type Success
}

function Main {
    try {
        Test-Prerequisites
        Invoke-WithRetry { Install-GCloudSDK } "Instalação do Google Cloud SDK"
        Invoke-WithRetry { Install-CloudSQLProxy } "Instalação do Cloud SQL Proxy"
        Ensure-HumanAuth
        Initialize-GCloudProject
        Start-CloudSQLProxy
        Write-ColoredMessage "Script concluído com sucesso." -Type Success
    } catch {
        Write-ColoredMessage "Erro fatal - $($_.Exception.Message)" -Type Error
        exit 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Main
}
