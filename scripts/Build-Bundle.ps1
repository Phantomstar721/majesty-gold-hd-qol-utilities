<#
.SYNOPSIS
    Builds the distributable Workshop/release zip.

.DESCRIPTION
    Builds the self-contained installer from the utilities in this repository
    and packages the EXE, public README, and license.

.PARAMETER OutputPath
    Where to write the archive. Defaults to dist\majesty-qol-utilities.zip.

.PARAMETER SourceRoot
    Optional path to a complete set of legacy checkouts for source comparison.

.PARAMETER SkipSyncCheck
    Skip the legacy source comparison, including when SourceRoot is supplied.

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
$RootFiles = @("Majesty QoL Utilities.exe", "README.md", "LICENSE")

Write-Host "Majesty Gold HD QoL Utilities bundle build"
Write-Host "Bundle: $BundleRoot"
Write-Host "Output: $OutputPath"
Write-Host ""

if ($SourceRoot -and -not $SkipSyncCheck) {
    Write-Host "Comparing against the supplied legacy checkouts..."
    & (Join-Path $PSScriptRoot "Sync-Utilities.ps1") -SourceRoot $SourceRoot -Check
    if ($LASTEXITCODE -ne 0) { throw "The utilities differ from the supplied legacy checkouts." }
    Write-Host ""
}

# Build the self-contained app before staging the three public files.
& (Join-Path $PSScriptRoot "Build-Exe.ps1") -OutputDir $BundleRoot
if ($LASTEXITCODE -ne 0) { throw "The executable build failed." }

# Stage what ships, so the archive cannot pick up source or maintainer files.
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

    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }

    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $OutputPath

    $entries = Get-ChildItem -Path $staging -Recurse -File
    Write-Host ("Built {0}" -f $OutputPath)
    Write-Host ("  {0:N1} KB, {1} files" -f ((Get-Item $OutputPath).Length / 1KB), $entries.Count)
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
