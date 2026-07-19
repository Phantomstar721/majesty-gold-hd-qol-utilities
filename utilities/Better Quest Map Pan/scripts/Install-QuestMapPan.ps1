param(
    [string]$GamePath = "",
    [ValidateRange(1, 127)]
    [int]$EdgePixels = 64,
    [Nullable[int]]$OutsidePixels = $null,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$edgeArgs = @{
    EdgePixels = $EdgePixels
    DryRun = $DryRun
}
if ($GamePath) {
    $edgeArgs.GamePath = $GamePath
}
if ($OutsidePixels.HasValue) {
    $edgeArgs.OutsidePixels = $OutsidePixels
}

$dragArgs = @{
    DryRun = $DryRun
}
if ($GamePath) {
    $dragArgs.GamePath = $GamePath
}

Write-Host "Majesty Gold HD Better Quest Map Pan installer"
Write-Host ""

& (Join-Path $PSScriptRoot "Install-QuestMapEdgePan.ps1") @edgeArgs
Write-Host ""
& (Join-Path $PSScriptRoot "Install-QuestMapDragPan.ps1") @dragArgs

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete. No files were changed."
} else {
    Write-Host "Done. The quest map now has wider edge panning and left-click drag panning."
}
