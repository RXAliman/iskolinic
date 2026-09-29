<#
.SYNOPSIS
    Builds the IskoLinic Flutter desktop app and packages it as a Windows installer.

.DESCRIPTION
    Automates the release process:
    1. Reads the version from pubspec.yaml
    2. Runs flutter build windows --release with the correct environment flag
    3. Compiles the Inno Setup installer script into a distributable .exe

.PARAMETER BuildEnv
    The build environment. Determines which Google Drive version.json the app checks.
    - 'prod' (default): Production build for clinic PCs. Checks version.json.
    - 'dev': Development build for test machines. Checks version-dev.json.

.EXAMPLE
    # Production build
    .\build_and_package.ps1

    # Dev/test build
    .\build_and_package.ps1 -BuildEnv dev
#>

param(
    [ValidateSet('prod', 'dev')]
    [string]$BuildEnv = 'prod'
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     IskoLinic - Build and Package      " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# -- Step 0: Read version from pubspec.yaml
$pubspecPath = Join-Path $PSScriptRoot "pubspec.yaml"
if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at: $pubspecPath"
}

$pubspec = Get-Content $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspec, 'version:\s+(\S+)')
if (-not $versionMatch.Success) {
    throw "Could not read version from pubspec.yaml"
}

$fullVersion = $versionMatch.Groups[1].Value
$versionName = $fullVersion.Split('+')[0]

$envColor = if ($BuildEnv -eq 'prod') { 'Green' } else { 'Yellow' }

Write-Host "  App Version : $versionName" -ForegroundColor White
Write-Host "  Environment : $BuildEnv" -ForegroundColor $envColor
Write-Host ""

# -- Step 1: Flutter build
Write-Host "[1/2] Building Flutter Windows release..." -ForegroundColor Yellow

$flutterArgs = @('build', 'windows', '--release', "--dart-define=ENV=$BuildEnv")
Write-Host "  > flutter $($flutterArgs -join ' ')" -ForegroundColor DarkGray

& flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    throw "Flutter build failed with exit code $LASTEXITCODE"
}

Write-Host "  Flutter build complete." -ForegroundColor Green
Write-Host ""

# -- Step 2: Compile installer with Inno Setup
Write-Host "[2/2] Compiling installer with Inno Setup..." -ForegroundColor Yellow

# Search for ISCC.exe in common install locations
$isccPaths = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 5\ISCC.exe"
)

$iscc = $null
foreach ($path in $isccPaths) {
    if (Test-Path $path) {
        $iscc = $path
        break
    }
}

if (-not $iscc) {
    Write-Host ""
    Write-Host "  Inno Setup not found!" -ForegroundColor Red
    Write-Host "  Install it from: https://jrsoftware.org/isinfo.php" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The Flutter build is complete. You can find the release files at:" -ForegroundColor White
    Write-Host "  build\windows\x64\runner\Release\" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

$issPath = Join-Path $PSScriptRoot "installer.iss"
$outputFilename = "IskoLinic-Setup-$versionName"
if ($BuildEnv -ne 'prod') {
    $outputFilename = "$outputFilename-pre"
}
$isccArgs = @("/DMyAppVersion=$versionName", "/DMyOutputFilename=$outputFilename", $issPath)
Write-Host "  > $iscc $($isccArgs -join ' ')" -ForegroundColor DarkGray

& $iscc @isccArgs
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "          Build Complete!               " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Installer:   dist\$outputFilename.exe" -ForegroundColor White
Write-Host "  Version:     $versionName" -ForegroundColor White
Write-Host "  Environment: $BuildEnv" -ForegroundColor White
Write-Host ""
