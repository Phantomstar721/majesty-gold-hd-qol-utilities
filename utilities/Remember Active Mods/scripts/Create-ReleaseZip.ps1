$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$package = Join-Path $dist "majesty-gold-hd-remember-active-mods.zip"
$staging = Join-Path $dist "majesty-gold-hd-remember-active-mods"

if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
if (-not (Test-Path -LiteralPath $dist)) {
    New-Item -ItemType Directory -Path $dist | Out-Null
}
if (Test-Path -LiteralPath $package) {
    Remove-Item -LiteralPath $package -Force
}

New-Item -ItemType Directory -Path $staging | Out-Null

Copy-Item -LiteralPath (Join-Path $root "Install - Remember Active Mods.bat") -Destination $staging
Copy-Item -LiteralPath (Join-Path $root "Uninstall - Restore Stock Mod Selection.bat") -Destination $staging
Copy-Item -LiteralPath (Join-Path $root "README.md") -Destination $staging
Copy-Item -LiteralPath (Join-Path $root "LICENSE") -Destination $staging
Copy-Item -LiteralPath (Join-Path $root "scripts") -Destination $staging -Recurse

Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $package -CompressionLevel Optimal
Remove-Item -LiteralPath $staging -Recurse -Force

Write-Host "Created:"
Write-Host $package
