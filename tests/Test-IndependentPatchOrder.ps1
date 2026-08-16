param(
    [Parameter(Mandatory = $true)][string]$StockExe
)

$ErrorActionPreference = "Stop"
$bundleRoot = Split-Path -Parent $PSScriptRoot
$utilities = Join-Path $bundleRoot "utilities"

function Utility-Script {
    param([string]$Utility, [string]$Script)
    return Join-Path (Join-Path (Join-Path $utilities $Utility) "scripts") $Script
}

if (-not (Test-Path -LiteralPath $StockExe -PathType Leaf)) {
    throw "Stock EXE not found: $StockExe"
}

$genericInstall = Utility-Script "Generic Visitor Lists" "Install-GenericVisitorLists.ps1"
$genericRestore = Utility-Script "Generic Visitor Lists" "Restore-GenericVisitorLists.ps1"
$zoomInstall = Utility-Script "Remember Camera Zoom" "Install-RememberCameraZoom.ps1"
$zoomRestore = Utility-Script "Remember Camera Zoom" "Restore-RememberCameraZoom.ps1"
$modsInstall = Utility-Script "Remember Active Mods" "Install-ModPersistence.ps1"
$modsRestore = Utility-Script "Remember Active Mods" "Restore-ModPersistence.ps1"
$speedInstall = Utility-Script "Remember Game Speed" "Install-RememberGameSpeed.ps1"
$speedRestore = Utility-Script "Remember Game Speed" "Restore-RememberGameSpeed.ps1"

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("majesty-independent-order-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$testExe = Join-Path $testRoot "MajestyHD.exe"
Copy-Item -LiteralPath $StockExe -Destination $testExe

try {
    $before = (Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash

    # Deliberately create a non-bundle section order.
    & $genericInstall -GamePath $testRoot
    & $zoomInstall -GamePath $testRoot
    & $modsInstall -GamePath $testRoot
    & $speedInstall -GamePath $testRoot

    # Remove two middle/early sections, then prove both can reactivate in place.
    & $modsRestore -GamePath $testRoot
    & $genericRestore -GamePath $testRoot
    & $modsInstall -GamePath $testRoot
    & $genericInstall -GamePath $testRoot

    # Remove active patches in an order unrelated to section order.
    & $zoomRestore -GamePath $testRoot
    & $modsRestore -GamePath $testRoot
    & $genericRestore -GamePath $testRoot
    & $speedRestore -GamePath $testRoot

    # Once later sections are gone, another restore pass may physically remove
    # each already-inert section without changing the uninstall result.
    & $modsRestore -GamePath $testRoot
    & $zoomRestore -GamePath $testRoot
    & $genericRestore -GamePath $testRoot

    $after = (Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash
    if ($after -ne $before) {
        throw "Independent-order round trip did not restore the input executable: $before != $after"
    }
    Write-Host "PASS: independent section install, middle-section uninstall, reactivation, and exact restoration."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing cleanup outside the temporary directory."
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
