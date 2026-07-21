$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

function Invoke-UtilityScript {
    param(
        [string]$Name,
        [string]$RelativePath
    )

    $scriptPath = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Could not find $Name script at $scriptPath."
    }

    Write-Host ""
    Write-Host "== $Name =="
    & $scriptPath
}

Write-Host "Majesty Gold HD QoL Utilities installer"
Write-Host "This installs all bundled quality-of-life patches."
Write-Host ""

Invoke-UtilityScript "Skip Intro Videos" "utilities\Skip Intro Videos\scripts\Install-NoIntro.ps1"
Invoke-UtilityScript "Downloadable Quests Shortcut" "utilities\Downloadable Quests Shortcut\scripts\Install-DownloadableQuestShortcut.ps1"
Invoke-UtilityScript "Better Quest Map Pan" "utilities\Better Quest Map Pan\scripts\Install-QuestMapPan.ps1"
Invoke-UtilityScript "Remember Active Mods" "utilities\Remember Active Mods\scripts\Install-ModPersistence.ps1"
Invoke-UtilityScript "Remember Game Speed" "utilities\Remember Game Speed\scripts\Install-RememberGameSpeed.ps1"

Write-Host ""
Write-Host "Done. All bundled Majesty Gold HD QoL utilities are installed."
Write-Host "Launch Majesty Gold HD normally from Steam."
