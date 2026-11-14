# Bascule blue-green du backend SamaFile derrière Nginx (Windows).
# Usage : powershell -File scripts\blue-green-deploy.ps1 [-Action deploy|rollback]
param(
    [ValidateSet("deploy", "rollback")]
    [string]$Action = "deploy"
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker est introuvable."
}
if (-not (Test-Path ".env")) {
    throw "Copiez .env.example vers .env et remplacez les mots de passe."
}

$compose = @("compose", "--profile", "blue", "--profile", "green")
$activeDir = "nginx\active"
$colorFile = Join-Path $activeDir "color"
$upstreamFile = Join-Path $activeDir "upstream.conf"
New-Item -ItemType Directory -Force -Path $activeDir | Out-Null
if (-not (Test-Path $colorFile)) {
    Set-Content -Path $colorFile -Value "blue" -NoNewline
}

$current = (Get-Content $colorFile -Raw).Trim()
if ($current -ne "blue" -and $current -ne "green") {
    throw "Couleur inconnue : $current"
}
$other = $(if ($current -eq "blue") { "green" } else { "blue" })

$appPort = "8888"
if (Test-Path ".env") {
    $line = Select-String -Path ".env" -Pattern "^APP_PORT=" | Select-Object -Last 1
    if ($line) {
        $appPort = $line.Line.Split("=", 2)[1].Trim().Trim('"')
    }
}

function Write-Upstream([string]$Color) {
    @"
upstream samafile_api {
    server backend-${Color}:8000;
}
"@ | Set-Content -Path $upstreamFile -Encoding ascii
}

function Get-ServiceId([string]$Service) {
    $id = & docker @compose ps -aq $Service
    if (-not $id) { return "" }
    return "$id".Trim()
}

function Get-Health([string]$Service) {
    $id = Get-ServiceId $Service
    if (-not $id) { return "missing" }
    return docker inspect -f "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $id
}

function Wait-Healthy([string]$Service) {
    for ($i = 0; $i -lt 36; $i++) {
        $status = Get-Health $Service
        Write-Host "  $Service : $status"
        if ($status -eq "healthy") { return }
        Start-Sleep -Seconds 5
    }
    & docker @compose logs --tail 80 $Service
    throw "Le service $Service n'est pas devenu healthy."
}

function Invoke-Reload {
    & docker @compose up -d proxy frontend
    if ($LASTEXITCODE -ne 0) { throw "Démarrage du proxy impossible." }
    for ($i = 0; $i -lt 15; $i++) {
        & docker @compose exec -T proxy nginx -s reload
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 2
    }
    throw "Impossible de recharger Nginx."
}

function Invoke-Smoke {
    $url = "http://127.0.0.1:$appPort/health"
    for ($i = 0; $i -lt 15; $i++) {
        try {
            $body = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 5
            if ($body.Content -match '"status"') {
                Write-Host "Santé OK : $url"
                return
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    throw "Contrôle de santé échoué : $url"
}

function Invoke-Pull([string]$Color) {
    if ($env:REQUIRE_PULL -eq "1") {
        & docker @compose pull "backend-$Color" frontend
        if ($LASTEXITCODE -ne 0) { throw "Téléchargement des images impossible." }
    }
}

function Start-Color([string]$Color) {
    Invoke-Pull $Color
    & docker @compose up -d db
    if ($LASTEXITCODE -ne 0) { throw "Démarrage de PostgreSQL impossible." }
    Wait-Healthy "db"
    & docker @compose up -d --force-recreate --no-deps "backend-$Color"
    if ($LASTEXITCODE -ne 0) { throw "Démarrage de backend-$Color impossible." }
    Wait-Healthy "backend-$Color"
    Write-Upstream $Color
    & docker @compose up -d --force-recreate --no-deps frontend
    if ($LASTEXITCODE -ne 0) { throw "Démarrage du frontend impossible." }
    Invoke-Reload
    Set-Content -Path $colorFile -Value $Color -NoNewline
    Invoke-Smoke
}

if ($Action -eq "rollback") {
    Write-Host "Retour vers backend-$other."
    if ((Get-Health "backend-$other") -eq "missing") {
        throw "Aucun conteneur backend-$other à redémarrer."
    }
    & docker @compose start "backend-$other"
    if ($LASTEXITCODE -ne 0) { throw "Redémarrage impossible." }
    Wait-Healthy "backend-$other"
    Write-Upstream $other
    Invoke-Reload
    Set-Content -Path $colorFile -Value $other -NoNewline
    & docker @compose stop "backend-$current"
    Invoke-Smoke
    exit 0
}

if ((Get-Health "backend-$current") -ne "healthy") {
    Write-Host "Premier démarrage sur backend-$current."
    Start-Color $current
    exit 0
}

Write-Host "Couleur active : $current. Nouvelle version sur backend-$other."
Invoke-Pull $other
& docker @compose up -d db frontend
if ($LASTEXITCODE -ne 0) { throw "Démarrage db/frontend impossible." }
Wait-Healthy "db"
& docker @compose up -d --force-recreate --no-deps "backend-$other"
if ($LASTEXITCODE -ne 0) { throw "Démarrage de backend-$other impossible." }
try {
    Wait-Healthy "backend-$other"
} catch {
    Write-Host "Basculement annulé. backend-$current reste en service."
    throw
}
Write-Upstream $other
Invoke-Reload
try {
    Invoke-Smoke
} catch {
    Write-Host "Contrôle échoué. Retour immédiat sur backend-$current."
    Write-Upstream $current
    Invoke-Reload
    throw
}
Set-Content -Path $colorFile -Value $other -NoNewline
& docker @compose stop "backend-$current"
Write-Host "Trafic basculé vers backend-$other."
