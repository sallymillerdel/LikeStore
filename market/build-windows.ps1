# Build the LikeStore Windows client as a portable ZIP into ..\incoming\.
#
#   powershell -ExecutionPolicy Bypass -File market\build-windows.ps1
#
# Writes, like every other app's portable build (MARKET_SPEC.md section 9):
#
#   incoming\com.likestore.market-win-<version>.zip
#   incoming\com.likestore.market-win-<version>.json
#
# <version> comes from pubspec.yaml (the part before "+"). Bump it before
# publishing a new store version.

$ErrorActionPreference = 'Stop'

$here     = $PSScriptRoot
$incoming = Join-Path (Split-Path $here -Parent) 'incoming'
$id       = (Get-Content (Join-Path (Split-Path $here -Parent) 'market.json') -Raw | ConvertFrom-Json).marketAppId
$line     = Select-String -Path (Join-Path $here 'pubspec.yaml') -Pattern '^version:\s*([^\s+]+)' | Select-Object -First 1
$version  = $line.Matches[0].Groups[1].Value

Push-Location $here
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
} finally {
    Pop-Location
}

$release = Join-Path $here 'build\windows\x64\runner\Release'
$zip     = Join-Path $incoming "$id-win-$version.zip"
$meta    = Join-Path $incoming "$id-win-$version.json"
New-Item -ItemType Directory -Force $incoming | Out-Null
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip

$info = [ordered]@{
    id          = $id
    name        = 'LikeStore'
    platform    = 'windows'
    package     = 'zip'
    entry       = 'LikeStore.exe'
    versionName = $version
    sha256      = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    sizeBytes   = (Get-Item $zip).Length
}
[IO.File]::WriteAllText($meta, ($info | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $zip"
Write-Host "Wrote $meta"
