param(
    [string]$GamePath = "",
    [string]$PrefsPath = "",
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

    $command = Get-Command -Name $scriptPath -CommandType ExternalScript

    # Forward only what each utility actually accepts. Skip Intro Videos edits
    # the Majesty preferences file rather than the game folder, so it takes
    # -PrefsPath instead of -GamePath.
    $arguments = @{}
    if ($GamePath -and $command.Parameters.ContainsKey("GamePath")) {
        $arguments["GamePath"] = $GamePath
    }
    if ($PrefsPath -and $command.Parameters.ContainsKey("PrefsPath")) {
        $arguments["PrefsPath"] = $PrefsPath
    }

    Write-Host ""
    Write-Host "== $Name =="
    if ($DryRun) {
        if (-not $command.Parameters.ContainsKey("DryRun")) {
            Write-Host "$Name does not expose a dry-run mode; skipped without changes."
            return
        }
        $arguments["DryRun"] = $true
    }

    & $scriptPath @arguments
}

Write-Host "Majesty Gold HD QoL Utilities installer"
Write-Host "This installs all bundled quality-of-life patches."
if ($GamePath) {
    Write-Host "Game path: $GamePath"
} else {
    Write-Host "Game path: auto-detected by each utility."
}
if ($PrefsPath) {
    Write-Host "Prefs path: $PrefsPath"
}
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

# This order keeps the combined log stable. Each utility independently owns,
# disables, and reuses its private section, so individual install order does
# not affect whether another utility can later be removed.
Invoke-UtilityScript "Skip Intro Videos" "utilities\Skip Intro Videos\scripts\Install-NoIntro.ps1"
Invoke-UtilityScript "Downloadable Quests Shortcut" "utilities\Downloadable Quests Shortcut\scripts\Install-DownloadableQuestShortcut.ps1"
Invoke-UtilityScript "Quest Map Drag" "utilities\Quest Map Drag\scripts\Install-QuestMapDragPan.ps1"
Invoke-UtilityScript "Unlock All Quests" "utilities\Unlock All Quests\scripts\Install-UnlockAllQuests.ps1"
Invoke-UtilityScript "Suppress All Message Flags" "utilities\Suppress All Message Flags\scripts\Install-SuppressAllMessageFlags.ps1"
Invoke-UtilityScript "Remember Active Mods" "utilities\Remember Active Mods\scripts\Install-ModPersistence.ps1"
Invoke-UtilityScript "Remember Game Speed" "utilities\Remember Game Speed\scripts\Install-RememberGameSpeed.ps1"
Invoke-UtilityScript "Remember Camera Zoom" "utilities\Remember Camera Zoom\scripts\Install-RememberCameraZoom.ps1"
Invoke-UtilityScript "Generic Visitor Lists" "utilities\Generic Visitor Lists\scripts\Install-GenericVisitorLists.ps1"

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete. Nothing was changed."
} else {
    Write-Host "Done. All bundled Majesty Gold HD QoL utilities are installed."
    Write-Host "Launch Majesty Gold HD normally from Steam."
}
