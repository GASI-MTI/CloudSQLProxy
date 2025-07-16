#Requires -Version 5.1
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
    [string]$ProjetoGCP = "plataformagovdigital-gcp-main",
    [Parameter(Mandatory = $false)]
    [string]$InstanciaGCP = "plataformagovdigital-gcp-main:southamerica-east1:cluster-postgresql-dev",
    #[string]$InstanciaGCP = "plataformagovdigital-gcp-main:southamerica-east1:cluster-postgresql",
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
        Start-Sleep -Seconds 2
        $maxWaitTime = 30; $waitTime = 0; $found = $false
        while ($waitTime -lt $maxWaitTime -and -not $found) {
            if (Test-CommandExists "gcloud") {
                $found = $true
                Write-ColoredMessage "Google Cloud SDK detectado com sucesso!" -Type Success
                break
            }
            Write-Host "." -NoNewline -ForegroundColor Yellow
            Start-Sleep -Seconds 2; $waitTime += 2
        }
        Write-Host ""
        if (-not $found) {
            Write-ColoredMessage "Google Cloud SDK não foi detectado automaticamente" -Type Warning
            Write-ColoredMessage "Isso pode acontecer se o PATH não foi atualizado ainda" -Type Info
            Write-ColoredMessage "Pressione Enter para tentar continuar ou Ctrl+C para cancelar" -Type Info
            Read-Host
            if (Test-CommandExists "gcloud") {
                Write-ColoredMessage "Ótimo! Agora o gcloud foi detectado" -Type Success
            } else {
                Write-ColoredMessage "Continuando sem detecção automática do gcloud..." -Type Warning
            }
        }
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
            Write-ColoredMessage "Diretório criado - $ProxyDir" -Type Info
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
        try {
            $versionOutput = & $Paths.ProxyFinal --version 2>&1
            Write-ColoredMessage "Cloud SQL Proxy instalado com sucesso - $($Paths.ProxyFinal)" -Type Success
            Write-ColoredMessage "Versão - $versionOutput" -Type Info
        } catch {
            Write-ColoredMessage "Proxy baixado mas não é executável. Verifique se o arquivo não está corrompido." -Type Warning
        }
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
    if (-not $activeUser -or $activeUser -match "compute@developer\.gserviceaccount\.com") {
        Write-ColoredMessage "Login necessário! Será aberto o navegador para autenticação Google." -Type Warning
        Write-ColoredMessage "Use uma conta humana do GCP com permissão no projeto: $ProjetoGCP" -Type Info
        Write-ColoredMessage "Após login, retorne para o script." -Type Info
        Write-Host ""
        Read-Host "Pressione Enter para abrir o navegador e fazer login"
        & gcloud auth login
        $activeUser = & gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>$null
        if (-not $activeUser -or $activeUser -match "compute@developer\.gserviceaccount\.com") {
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
    Write-ColoredMessage "Conectando à instância - $InstanciaGCP" -Type Info
    Write-Host ""
    while ($true) {
        try {
            & $Paths.ProxyFinal $InstanciaGCP --gcloud-auth
            Write-ColoredMessage "Proxy encerrado normalmente" -Type Info
            break
        } catch {
            Write-ColoredMessage "Proxy falhou - $($_.Exception.Message)" -Type Error
            Write-ColoredMessage "Reiniciando em $($Config.RetryDelaySeconds) segundos..." -Type Warning
            Start-Sleep -Seconds $Config.RetryDelaySeconds
        }
    }
    Write-ColoredMessage "Cloud SQL Proxy finalizado" -Type Info
}

function Test-Prerequisites {
    Write-ColoredMessage "Verificando pré-requisitos..." -Type Info
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "PowerShell 5.1 ou superior é necessário. Versão atual - $($PSVersionTable.PSVersion)"
    }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if (-not $IsWindows) {
            throw "Este script foi desenvolvido para Windows. SO atual - $($PSVersionTable.Platform)"
        }
    }
    $internetConnected = $false
    try {
        if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
            $testConnection = Test-NetConnection -ComputerName "google.com" -Port 443 -InformationLevel Quiet -ErrorAction Stop -WarningAction SilentlyContinue
            $internetConnected = $testConnection
        }
    } catch {}
    if (-not $internetConnected) {
        try {
            $webRequest = [System.Net.WebRequest]::Create("https://google.com")
            $webRequest.Timeout = 5000
            $response = $webRequest.GetResponse()
            $response.Close()
            $internetConnected = $true
        } catch {}
    }
    if (-not $internetConnected) { throw "Sem conectividade com a internet. Verifique sua conexão." }
    try {
        $testFile = Join-Path $ProxyDir "test_write_permissions.tmp"
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    } catch {
        throw "Sem permissões de escrita no diretório - $ProxyDir"
    }
    Write-ColoredMessage "Pré-requisitos verificados com sucesso" -Type Success
}

function Main {
    try {
        Write-ColoredMessage "=== Cloud SQL Proxy Setup - Iniciando ===" -Type Info
        Write-ColoredMessage "Projeto - $ProjetoGCP" -Type Info
        Write-ColoredMessage "Instância - $InstanciaGCP" -Type Info
        Write-ColoredMessage "Versão do Proxy - $ProxyVersion" -Type Info
        Write-ColoredMessage "Diretório - $ProxyDir" -Type Info
        Write-Host ""
        Test-Prerequisites
        Invoke-WithRetry -ScriptBlock { Install-GCloudSDK } -ActionDescription "Instalação do Google Cloud SDK"
        Invoke-WithRetry -ScriptBlock { Install-CloudSQLProxy } -ActionDescription "Instalação do Cloud SQL Proxy"
        Ensure-HumanAuth
        Initialize-GCloudProject
        Start-CloudSQLProxy
        Write-ColoredMessage "=== Script concluído com sucesso ===" -Type Success
    } catch {
        Write-ColoredMessage "Erro fatal - $($_.Exception.Message)" -Type Error
        if ($_.Exception.GetType().Name -eq "RuntimeException") {
            Write-ColoredMessage "Detalhes - $($_.Exception.ToString())" -Type Error
        }
        if ($_.Exception.InnerException) {
            Write-ColoredMessage "Erro interno - $($_.Exception.InnerException.Message)" -Type Error
        }
        Write-ColoredMessage "Execute novamente com -Verbose para mais detalhes" -Type Info
        exit 1
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Main
}
