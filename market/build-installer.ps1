# Build the LikeStore Windows installer (Setup.exe) into ..\dist\.
#
#   powershell -ExecutionPolicy Bypass -File market\build-installer.ps1 [-NoBuild]
#
# Writes dist\LikeStore-Setup-<version>.exe, for the first install on a new PC.
# Later updates come through the store itself (the portable zip from
# build-windows.ps1), so this file is not published to the catalog.
#
# Needs Inno Setup 6 (winget install JRSoftware.InnoSetup). ISCC.exe is found
# through $env:ISCC, PATH, or the Inno Setup uninstall entry in the registry.
# -NoBuild reuses the existing build\windows\x64\runner\Release folder.

param([switch]$NoBuild)

$ErrorActionPreference = 'Stop'

function Find-Iscc {
    if ($env:ISCC -and (Test-Path $env:ISCC)) { return $env:ISCC }
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1'
    foreach ($k in $keys) {
        $loc = (Get-ItemProperty $k -ErrorAction SilentlyContinue).InstallLocation
        if ($loc -and (Test-Path (Join-Path $loc 'ISCC.exe'))) { return (Join-Path $loc 'ISCC.exe') }
    }
    throw 'ISCC.exe (Inno Setup 6) not found. Install it with: winget install JRSoftware.InnoSetup'
}

$here    = $PSScriptRoot
$dist    = Join-Path (Split-Path $here -Parent) 'dist'
$line    = Select-String -Path (Join-Path $here 'pubspec.yaml') -Pattern '^version:\s*([^\s+]+)' | Select-Object -First 1
$version = $line.Matches[0].Groups[1].Value
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "pubspec.yaml version '$version' is not plain MAJOR.MINOR.PATCH (Windows file versions need numbers only)."
}
$iscc = Find-Iscc

if (-not $NoBuild) {
    Push-Location $here
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
    } finally {
        Pop-Location
    }
}

$release = Join-Path $here 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'LikeStore.exe'))) {
    throw "No LikeStore.exe in $release. Run without -NoBuild."
}

New-Item -ItemType Directory -Force $dist | Out-Null
& $iscc /Q "/DAppVersion=$version" "/DSourceDir=$release" "/DOutputDir=$dist" (Join-Path $here 'installer\LikeStore.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }
Write-Host "Wrote $(Join-Path $dist "LikeStore-Setup-$version.exe")"
