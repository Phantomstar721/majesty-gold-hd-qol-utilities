<#
.SYNOPSIS
    Stages the current QoL app for upload through Majesty's RGSEditor.

.DESCRIPTION
    Stages a built executable, instructions, preview and RGSEditor project
    inside the repository, then writes the executable checksum.
#>
param(
    [string]$ProjectPath = "dist\workshop-upload",
    [string]$ExecutablePath = "Majesty QoL Utilities.exe"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($ProjectPath)) {
    $ProjectPath = Join-Path $RepoRoot $ProjectPath
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if (-not $ProjectPath.StartsWith($RepoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Workshop staging must be inside the repository: $ProjectPath"
}
$ContentPath = Join-Path $ProjectPath "content"
if (-not [IO.Path]::IsPathRooted($ExecutablePath)) {
    $ExecutablePath = Join-Path $RepoRoot $ExecutablePath
}
$ExePath = [IO.Path]::GetFullPath($ExecutablePath)
$PreviewSource = Join-Path $RepoRoot "workshop\workshop-preview.jpg"
$PreviewPath = Join-Path $ProjectPath "workshop-preview.jpg"
$ProjectName = "MajestyQoLUtilities.mswproj"
$WorkshopProject = [System.Xml.XmlDocument]::new()
$WorkshopProject.PreserveWhitespace = $true
$WorkshopProject.Load((Join-Path $RepoRoot "workshop\$ProjectName"))
$WorkshopProject.SelectSingleNode("/Majesty/SteamWorkshop/ContentPath").InnerText = $ContentPath
$WorkshopProject.SelectSingleNode("/Majesty/SteamWorkshop/PreviewImagePath").InnerText = $PreviewPath

if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { throw "Build the QoL executable first: $ExePath" }
if (-not (Test-Path -LiteralPath $PreviewSource -PathType Leaf)) { throw "Workshop preview image not found: $PreviewSource" }
New-Item -ItemType Directory -Path $ContentPath -Force | Out-Null

Copy-Item -LiteralPath $PreviewSource -Destination $PreviewPath -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot "workshop\START HERE.txt") -Destination (Join-Path $ContentPath "START HERE.txt") -Force
Copy-Item -LiteralPath $ExePath -Destination (Join-Path $ContentPath "Majesty QoL Utilities.exe") -Force
$WorkshopProject.Save((Join-Path $ProjectPath $ProjectName))

$hash = (Get-FileHash -LiteralPath $ExePath -Algorithm SHA256).Hash.ToUpperInvariant()
[IO.File]::WriteAllText((Join-Path $ProjectPath "SHA256.txt"), "$hash  Majesty QoL Utilities.exe`r`n", [Text.Encoding]::ASCII)

Write-Host "Workshop upload staged: $ProjectPath"
Write-Host "  EXE:    $((Get-Item -LiteralPath $ExePath).Length) bytes"
Write-Host "  SHA256: $hash"
