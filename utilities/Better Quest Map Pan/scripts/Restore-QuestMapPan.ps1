param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$restoreArgs = @{
    DryRun = $DryRun
}
if ($GamePath) {
    $restoreArgs.GamePath = $GamePath
}

Write-Host "Majesty Gold HD Better Quest Map Pan restore"
Write-Host ""

& (Join-Path $PSScriptRoot "Restore-QuestMapDragPan.ps1") @restoreArgs
Write-Host ""
& (Join-Path $PSScriptRoot "Restore-QuestMapEdgePan.ps1") @restoreArgs

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete. No files were changed."
} else {
    Write-Host "Done. The quest map panning behavior is restored to stock."
}
