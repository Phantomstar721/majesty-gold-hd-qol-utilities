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

Write-Host "Majesty Gold HD QoL Utilities restore"
Write-Host "This uninstalls all bundled quality-of-life patches."
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

# Reverse of the install order. Utilities that append a PE section can only be
# removed while they are the last one added, so the newest must go first.
#
# If you also installed the standalone Speedrun Timer (.msrt) or the Freestyle
# Custom CAM Fix (.mfsp), remove those first, newest first, since their sections
# sit after everything here.
Invoke-UtilityScript "Generic Visitor Lists" "utilities\Generic Visitor Lists\scripts\Restore-GenericVisitorLists.ps1"
Invoke-UtilityScript "Remember Camera Zoom" "utilities\Remember Camera Zoom\scripts\Restore-RememberCameraZoom.ps1"
Invoke-UtilityScript "Remember Game Speed" "utilities\Remember Game Speed\scripts\Restore-RememberGameSpeed.ps1"
Invoke-UtilityScript "Remember Active Mods" "utilities\Remember Active Mods\scripts\Restore-ModPersistence.ps1"
Invoke-UtilityScript "Suppress All Message Flags" "utilities\Suppress All Message Flags\scripts\Restore-SuppressAllMessageFlags.ps1"
Invoke-UtilityScript "Unlock All Quests" "utilities\Unlock All Quests\scripts\Restore-UnlockAllQuests.ps1"
Invoke-UtilityScript "Quest Map Drag" "utilities\Quest Map Drag\scripts\Restore-QuestMapDragPan.ps1"
Invoke-UtilityScript "Downloadable Quests Shortcut" "utilities\Downloadable Quests Shortcut\scripts\Restore-CustomQuestButton.ps1"
Invoke-UtilityScript "Skip Intro Videos" "utilities\Skip Intro Videos\scripts\Uninstall-NoIntro.ps1"

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete. Nothing was changed."
} else {
    Write-Host "Done. Stock Majesty Gold HD behavior is restored for the bundled utilities."
}
