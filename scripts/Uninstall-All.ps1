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

Write-Host "Majesty Gold HD QoL Utilities restore"
Write-Host "This uninstalls all bundled quality-of-life patches."
Write-Host ""

Invoke-UtilityScript "Remember Active Mods" "utilities\Remember Active Mods\scripts\Restore-ModPersistence.ps1"
Invoke-UtilityScript "Better Quest Map Pan" "utilities\Better Quest Map Pan\scripts\Restore-QuestMapPan.ps1"
Invoke-UtilityScript "Downloadable Quests Shortcut" "utilities\Downloadable Quests Shortcut\scripts\Restore-CustomQuestButton.ps1"
Invoke-UtilityScript "Skip Intro Videos" "utilities\Skip Intro Videos\scripts\Uninstall-NoIntro.ps1"

Write-Host ""
Write-Host "Done. Stock Majesty Gold HD behavior is restored for the bundled utilities."

