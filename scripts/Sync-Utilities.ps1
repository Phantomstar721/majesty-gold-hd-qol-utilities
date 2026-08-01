<#
.SYNOPSIS
    Vendors each utility into this bundle from its own source repository.

.DESCRIPTION
    Every utility here is also published standalone from its own repo. That repo
    is the source of truth; this bundle carries a copy so it can be downloaded
    and run as one piece.

    Copies drift. Before this script existed the copies were kept in step by
    hand, and they did not stay in step: five README files here still described
    the old Steam discovery behaviour and were missing the warning that the
    _*_originals folders are not stock backups.

    Run -Check before packaging or committing. It changes nothing and exits 1 if
    anything has drifted, so it can gate a release.

.PARAMETER SourceRoot
    Folder holding the six utility repositories. Defaults to this repository's
    parent, which is the normal side-by-side workspace layout.

.PARAMETER Check
    Report drift and exit 1 without writing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Sync-Utilities.ps1 -Check

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Sync-Utilities.ps1
#>
param(
    [string]$SourceRoot = "",
    [switch]$Check
)

$ErrorActionPreference = "Stop"

$BundleRoot = Split-Path -Parent $PSScriptRoot

if (-not $SourceRoot) {
    $SourceRoot = Split-Path -Parent $BundleRoot
}

# Bundle utility folder -> source repository name. The folder name here is what
# users see, so it does not always match the repository name.
$UtilityRepos = [ordered]@{
    "Downloadable Quests Shortcut" = "majesty-gold-hd-downloadable-quests-shortcut"
    "Quest Map Drag"               = "majesty-gold-hd-quest-map-drag"
    "Remember Active Mods"         = "majesty-gold-hd-remember-active-mods"
    "Remember Camera Zoom"         = "majesty-gold-hd-remember-camera-zoom"
    "Remember Game Speed"          = "majesty-gold-hd-remember-game-speed"
    "Skip Intro Videos"            = "majesty-gold-hd-skip-intro-videos"
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
        "`nClone them beside this repository, or pass -SourceRoot.")
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
