param(
    [switch]$DryRun
)

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
    if ($DryRun) {
        $command = Get-Command -Name $scriptPath -CommandType ExternalScript
        if ($command.Parameters.ContainsKey("DryRun")) {
            & $scriptPath -DryRun
        } else {
            Write-Host "$Name does not expose a dry-run mode; skipped without changes."
        }
    } else {
        & $scriptPath
    }
}

Write-Host "Majesty Gold HD QoL Utilities restore"
Write-Host "This uninstalls all bundled quality-of-life patches."
Write-Host ""

Invoke-UtilityScript "Remember Camera Zoom" "utilities\Remember Camera Zoom\scripts\Restore-RememberCameraZoom.ps1"
Invoke-UtilityScript "Remember Game Speed" "utilities\Remember Game Speed\scripts\Restore-RememberGameSpeed.ps1"
Invoke-UtilityScript "Remember Active Mods" "utilities\Remember Active Mods\scripts\Restore-ModPersistence.ps1"
Invoke-UtilityScript "Quest Map Drag" "utilities\Quest Map Drag\scripts\Restore-QuestMapDragPan.ps1"
Invoke-UtilityScript "Downloadable Quests Shortcut" "utilities\Downloadable Quests Shortcut\scripts\Restore-CustomQuestButton.ps1"
Invoke-UtilityScript "Skip Intro Videos" "utilities\Skip Intro Videos\scripts\Uninstall-NoIntro.ps1"

Write-Host ""
Write-Host "Done. Stock Majesty Gold HD behavior is restored for the bundled utilities."
