# Build the LikeStore Android client into ..\incoming\.
#
#   powershell -ExecutionPolicy Bypass -File market\build-android.ps1
#
# Signs with the shared release keystore from the environment:
#   ANDROID_KEYSTORE, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS,
#   ANDROID_KEY_PASSWORD (optional, defaults to the store password)
# Without ANDROID_KEYSTORE it refuses, unless -DebugKey is given: a store
# signed with a debug key cannot later be updated by a release-signed one.
#
# The version is "android" in versions.json, NAME+CODE: the "+N" part is the
# versionCode. Bump both before publishing a new store version.

param([switch]$DebugKey)

$ErrorActionPreference = 'Stop'

if (-not $env:ANDROID_KEYSTORE -and -not $DebugKey) {
    throw 'ANDROID_KEYSTORE is not set. Set the keystore variables, or pass -DebugKey for a test build.'
}
# Same toolchain the other app builds use, unless already configured.
if (-not $env:JAVA_HOME)    { $env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot' }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = 'D:\dev\android-sdk' }
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME

$here     = $PSScriptRoot
$incoming = Join-Path (Split-Path $here -Parent) 'incoming'
$id       = (Get-Content (Join-Path (Split-Path $here -Parent) 'market.json') -Raw | ConvertFrom-Json).marketAppId
$name, $code = (Get-Content (Join-Path $here 'versions.json') -Raw | ConvertFrom-Json).android -split '\+'

Push-Location $here
try {
    flutter build apk --release --target-platform android-arm,android-arm64 --build-name $name --build-number $code
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
} finally {
    Pop-Location
}

New-Item -ItemType Directory -Force $incoming | Out-Null
$out = Join-Path $incoming "$id.apk"
Copy-Item (Join-Path $here 'build\app\outputs\flutter-apk\app-release.apk') $out -Force
Write-Host "Wrote $out"
