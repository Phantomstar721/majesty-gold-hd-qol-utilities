<#
.SYNOPSIS
    Builds the distributable bundle zip from this working tree.

.DESCRIPTION
    The zip used to be assembled by hand, and it showed: the copy sitting in
    dist\ was three weeks stale and still contained a "Better Quest Map Pan"
    folder from before that utility was renamed to "Quest Map Drag". Nothing
    tied the archive to the tree it was supposedly built from.

    This script verifies the bundle is in sync with the source repositories,
    then builds the archive from the tree, so what ships is what is committed.

    Maintainer scripts are deliberately excluded. Someone who downloads the zip
    gets the installers and nothing else.

.PARAMETER OutputPath
    Where to write the archive. Defaults to dist\majesty-qol-utilities.zip.

.PARAMETER SourceRoot
    Passed through to Sync-Utilities.ps1 -Check.

.PARAMETER SkipSyncCheck
    Build without verifying against the source repositories. Only for building
    from a clone that does not have the utility repos beside it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Build-Bundle.ps1
#>
param(
    [string]$OutputPath = "",
    [string]$SourceRoot = "",
    [switch]$SkipSyncCheck
)

$ErrorActionPreference = "Stop"

$BundleRoot = Split-Path -Parent $PSScriptRoot

if (-not $OutputPath) {
    $OutputPath = Join-Path $BundleRoot "dist\majesty-qol-utilities.zip"
}

# What a user downloading the zip needs. Maintainer tooling stays out.
$RootFiles = @(
    "Install - All Majesty QoL Utilities.bat"
    "Uninstall - Restore Stock Majesty QoL.bat"
    "README.md"
    "LICENSE"
)
$ScriptFiles = @(
    "Install-All.ps1"
    "Uninstall-All.ps1"
)

Write-Host "Majesty Gold HD QoL Utilities bundle build"
Write-Host "Bundle: $BundleRoot"
Write-Host "Output: $OutputPath"
Write-Host ""

if ($SkipSyncCheck) {
    Write-Host "Sync check skipped by request."
    Write-Host ""
} else {
    Write-Host "Verifying the bundle matches its source repositories..."
    $checkArgs = @{ Check = $true }
    if ($SourceRoot) { $checkArgs["SourceRoot"] = $SourceRoot }
    & (Join-Path $PSScriptRoot "Sync-Utilities.ps1") @checkArgs
    if ($LASTEXITCODE -ne 0) {
        throw ("The bundle is out of sync with its source repositories. " +
            "Run scripts\Sync-Utilities.ps1 and commit the result, " +
            "or pass -SkipSyncCheck if you know the copies are correct.")
    }
    Write-Host ""
}

# Stage what ships, so the archive cannot pick up dist\, .git, .gitignore or
# the maintainer scripts by accident.
$staging = Join-Path ([IO.Path]::GetTempPath()) ("majesty-qol-bundle-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $staging -Force | Out-Null

try {
    foreach ($name in $RootFiles) {
        $from = Join-Path $BundleRoot $name
        if (-not (Test-Path -LiteralPath $from)) {
            throw "Missing bundle file: $from"
        }
        Copy-Item -LiteralPath $from -Destination (Join-Path $staging $name)
    }

    $stagingScripts = Join-Path $staging "scripts"
    New-Item -ItemType Directory -Path $stagingScripts -Force | Out-Null
    foreach ($name in $ScriptFiles) {
        $from = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $from)) {
            throw "Missing bundle script: $from"
        }
        Copy-Item -LiteralPath $from -Destination (Join-Path $stagingScripts $name)
    }

    $utilitiesSource = Join-Path $BundleRoot "utilities"
    if (-not (Test-Path -LiteralPath $utilitiesSource)) {
        throw "Missing utilities folder: $utilitiesSource"
    }
    Copy-Item -LiteralPath $utilitiesSource -Destination (Join-Path $staging "utilities") -Recurse

    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $OutputPath

    $entries = Get-ChildItem -Path $staging -Recurse -File
    $utilities = Get-ChildItem -Path (Join-Path $staging "utilities") -Directory

    Write-Host ("Built {0}" -f $OutputPath)
    Write-Host ("  {0:N1} KB, {1} files" -f ((Get-Item $OutputPath).Length / 1KB), $entries.Count)
    Write-Host ("  {0} utilities:" -f $utilities.Count)
    foreach ($utility in $utilities) {
        Write-Host ("    {0}" -f $utility.Name)
    }
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
