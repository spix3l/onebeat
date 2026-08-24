param(
  [string]$Version = "0.0.0",
  [string]$BuildNumber = "1"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$EngineBuild = Join-Path $RepoRoot "build-windows"
$AppRoot = Join-Path $RepoRoot "app"

cmake -S (Join-Path $RepoRoot "engine") -B $EngineBuild `
  -A x64 -DONEBEAT_BUILD_TESTS=OFF -DONEBEAT_WERROR=OFF
cmake --build $EngineBuild --config Release --target onebeat_engine --parallel 3

Push-Location $AppRoot
try {
  flutter pub get
  flutter build windows --release --build-name $Version --build-number $BuildNumber
} finally {
  Pop-Location
}

$Runner = Join-Path $AppRoot "build\windows\x64\runner\Release"
$Engine = Join-Path $EngineBuild "Release\onebeat_engine.dll"
Copy-Item $Engine (Join-Path $Runner "onebeat_engine.dll") -Force

$PackageRoot = Join-Path $RepoRoot "artifacts\OneBeat-Windows"
$Archive = Join-Path $RepoRoot "artifacts\OneBeat-Windows-x64.zip"
New-Item -ItemType Directory -Force (Split-Path -Parent $PackageRoot) | Out-Null
if (Test-Path $PackageRoot) { Remove-Item $PackageRoot -Recurse -Force }
Copy-Item $Runner $PackageRoot -Recurse
if (Test-Path $Archive) { Remove-Item $Archive -Force }
Compress-Archive -Path $PackageRoot -DestinationPath $Archive
Write-Host "Windows artifact: $Archive"
