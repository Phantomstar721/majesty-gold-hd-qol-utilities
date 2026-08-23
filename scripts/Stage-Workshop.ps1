<#
.SYNOPSIS
    Stages the current QoL app for upload through Majesty's RGSEditor.

.DESCRIPTION
    Copies the built executable, Workshop instructions, and RGSEditor project
    metadata into the local SDK upload project, then regenerates SHA256.txt.
    The existing workshop-preview.jpg is retained.
#>
param(
    [string]$ProjectPath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD\SDK\Mods\MajestyQoLUtilitiesUpload"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ContentPath = Join-Path $ProjectPath "content"
$ExePath = Join-Path $RepoRoot "Majesty QoL Utilities.exe"
$PreviewPath = Join-Path $ProjectPath "workshop-preview.jpg"

if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { throw "Build the QoL executable first: $ExePath" }
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) { throw "RGSEditor project folder not found: $ProjectPath" }
if (-not (Test-Path -LiteralPath $PreviewPath -PathType Leaf)) { throw "Workshop preview image not found: $PreviewPath" }
if (-not (Test-Path -LiteralPath $ContentPath -PathType Container)) { New-Item -ItemType Directory -Path $ContentPath | Out-Null }

Copy-Item -LiteralPath (Join-Path $RepoRoot "workshop\MajestyQoLUtilities.mswproj") -Destination (Join-Path $ProjectPath "MajestyQoLUtilities.mswproj") -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "workshop\START HERE.txt") -Destination (Join-Path $ContentPath "START HERE.txt") -Force
Copy-Item -LiteralPath $ExePath -Destination (Join-Path $ContentPath "Majesty QoL Utilities.exe") -Force

$hash = (Get-FileHash -LiteralPath $ExePath -Algorithm SHA256).Hash.ToUpperInvariant()
[IO.File]::WriteAllText((Join-Path $ProjectPath "SHA256.txt"), "$hash  Majesty QoL Utilities.exe`r`n", [Text.Encoding]::ASCII)

Write-Host "Workshop upload staged: $ProjectPath"
Write-Host "  EXE:    $((Get-Item -LiteralPath $ExePath).Length) bytes"
Write-Host "  SHA256: $hash"
