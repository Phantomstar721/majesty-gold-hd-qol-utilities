<#
.SYNOPSIS
    Compares or imports utilities from a complete set of legacy checkouts.

.DESCRIPTION
    Normal development and packaging use the utilities in this repository.
    Use -Check to compare a separately supplied legacy source tree without
    writing files.

.PARAMETER SourceRoot
    Folder holding all the legacy standalone utility checkouts.

.PARAMETER Check
    Report drift and exit 1 without writing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Sync-Utilities.ps1 -SourceRoot C:\legacy-checkouts -Check

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Sync-Utilities.ps1 -SourceRoot C:\legacy-checkouts
#>
param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$BundleRoot = Split-Path -Parent $PSScriptRoot

# Bundle utility folder -> source repository name. The folder name here is what
# users see, so it does not always match the repository name.
$UtilityRepos = [ordered]@{
    "Downloadable Quests Shortcut" = "majesty-gold-hd-downloadable-quests-shortcut"
    "Generic Visitor Lists"         = "majesty-gold-hd-generic-visitor-lists"
    "Lower Tracking Window"        = "majesty-gold-hd-lower-tracking-window"
    "Quest Map Drag"               = "majesty-gold-hd-quest-map-drag"
    "Remember Active Mods"         = "majesty-gold-hd-remember-active-mods"
    "Remember Camera Zoom"         = "majesty-gold-hd-remember-camera-zoom"
    "Remember Game Speed"          = "majesty-gold-hd-remember-game-speed"
    "Skip Intro Videos"            = "majesty-gold-hd-skip-intro-videos"
    "Suppress All Message Flags"   = "majesty-gold-hd-suppress-all-message-flags"
    "Unlock All Quests"            = "majesty-gold-hd-unlock-all-quests"
}

# What gets vendored. Everything a user needs to run the utility standalone,
# and nothing that only matters to whoever develops it: no .git, no research
# notes, no docs folder, no test fixtures.
$IncludePatterns = @(
    "*.bat"
    "LICENSE"
    "README.md"
    "scripts\*.ps1"
    "tools\*.py"
)

function Get-VendoredFiles {
    param([string]$RepoPath)

    $files = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in $IncludePatterns) {
        $full = Join-Path $RepoPath $pattern
        foreach ($item in Get-ChildItem -Path $full -File -ErrorAction SilentlyContinue) {
            $relative = $item.FullName.Substring($RepoPath.Length + 1)
            if (-not $files.Contains($relative)) {
                $files.Add($relative)
            }
        }
    }
    return $files
}

function Test-SameFile {
    param([string]$Left, [string]$Right)

    if (-not (Test-Path -LiteralPath $Right)) { return $false }
    return (Get-FileHash -LiteralPath $Left).Hash -eq (Get-FileHash -LiteralPath $Right).Hash
}

Write-Host "Majesty Gold HD QoL Utilities bundle sync"
Write-Host "Bundle: $BundleRoot"
Write-Host "Source: $SourceRoot"
if ($Check) {
    Write-Host "Mode:   check only, nothing will be written"
}
Write-Host ""

# Fail early and clearly if the workspace is not laid out as expected, rather
# than silently vendoring a partial bundle.
$missingRepos = @()
foreach ($repo in $UtilityRepos.Values) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $repo))) {
        $missingRepos += $repo
    }
}
if ($missingRepos.Count -gt 0) {
    throw ("Could not find these source repositories under ${SourceRoot}:`n  " +
        ($missingRepos -join "`n  ") +
        "`nSupply a folder with the complete set of legacy checkouts.")
}

$updated = @()
$added = @()
$stale = @()
$unchanged = 0

foreach ($utility in $UtilityRepos.Keys) {
    $repoPath = Join-Path $SourceRoot $UtilityRepos[$utility]
    $bundlePath = Join-Path (Join-Path $BundleRoot "utilities") $utility

    $sourceFiles = Get-VendoredFiles -RepoPath $repoPath
    if ($sourceFiles.Count -eq 0) {
        throw "No vendorable files found in $repoPath. Check the include patterns."
    }

    foreach ($relative in $sourceFiles) {
        $from = Join-Path $repoPath $relative
        $to = Join-Path $bundlePath $relative

        if (Test-SameFile -Left $from -Right $to) {
            $unchanged++
            continue
        }

        if (Test-Path -LiteralPath $to) {
            $updated += "$utility\$relative"
        } else {
            $added += "$utility\$relative"
        }

        if (-not $Check) {
            $parent = Split-Path -Parent $to
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
    }

    # Files here with no counterpart in the source repo. Usually a leftover from
    # a rename, which is how a stale copy survives unnoticed.
    if (Test-Path -LiteralPath $bundlePath) {
        foreach ($item in Get-ChildItem -Path $bundlePath -Recurse -File) {
            $relative = $item.FullName.Substring($bundlePath.Length + 1)
            if (-not (Test-Path -LiteralPath (Join-Path $repoPath $relative))) {
                $stale += "$utility\$relative"
            }
        }
    }
}

foreach ($entry in $added)   { Write-Host "  added   $entry" }
foreach ($entry in $updated) { Write-Host "  updated $entry" }
foreach ($entry in $stale)   { Write-Host "  ORPHAN  $entry (no matching file in the source repo)" }

Write-Host ""
Write-Host ("In sync: {0}   Added: {1}   Updated: {2}   Orphaned: {3}" -f
    $unchanged, $added.Count, $updated.Count, $stale.Count)

$drift = $added.Count + $updated.Count + $stale.Count

if ($Check) {
    if ($drift -gt 0) {
        Write-Host ""
        Write-Host "Bundle is OUT OF SYNC with the source repositories."
        Write-Host "Run this script without -Check to update it."
        exit 1
    }
    Write-Host ""
    Write-Host "Bundle matches every source repository."
    exit 0
}

if ($stale.Count -gt 0) {
    Write-Host ""
    Write-Host "Orphaned files were left in place; remove them by hand if the"
    Write-Host "utility was renamed or a file was intentionally dropped."
}

Write-Host ""
if ($drift -eq 0) {
    Write-Host "Nothing to do. The bundle was already in sync."
} else {
    Write-Host "Bundle updated. Review the changes before committing."
}
