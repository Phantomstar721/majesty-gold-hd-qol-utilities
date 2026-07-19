param(
    [string]$GamePath = "",
    [ValidateRange(1, 127)]
    [int]$EdgePixels = 64,
    [Nullable[int]]$OutsidePixels = $null,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$EdgeOffsets = @(0x5DFFA, 0x5E021, 0x5E04F, 0x5E084, 0x5E112, 0x5E132, 0x5E150, 0x5E180)
$OutsideNegativeOffsets = @(0x5E003, 0x5E058)
$OutsidePositiveOffsets = @(0x5E03B, 0x5E09E)

function Get-MajestyPath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        return $RequestedPath
    }

    if (Test-Path -LiteralPath $DefaultGamePath) {
        return $DefaultGamePath
    }

    $steamRoots = @()
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $installPath = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($installPath) {
                $steamRoots += $installPath
            }
        } catch {
        }
    }

    foreach ($root in $steamRoots | Select-Object -Unique) {
        $candidate = Join-Path $root "steamapps\common\Majesty HD"
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    foreach ($root in $steamRoots | Select-Object -Unique) {
        $libraryFile = Join-Path $root "steamapps\libraryfolders.vdf"
        if (-not (Test-Path -LiteralPath $libraryFile)) {
            continue
        }

        foreach ($line in Get-Content -LiteralPath $libraryFile) {
            if ($line -match '"path"\s+"([^"]+)"') {
                $libraryRoot = $Matches[1] -replace "\\\\", "\"
                $candidate = Join-Path $libraryRoot "steamapps\common\Majesty HD"
                if (Test-Path -LiteralPath $candidate) {
                    return $candidate
                }
            }
        }
    }

    throw "Could not find Majesty HD. Re-run with -GamePath ""C:\Path\To\Majesty HD""."
}

function Assert-FileWritable {
    param([string]$Path)

    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot patch MajestyHD.exe because it is in use or not writable. Close Majesty Gold HD and run this installer again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Assert-InstructionShape {
    param([byte[]]$Bytes, [int]$ImmediateOffset)

    if ($ImmediateOffset -lt 2 -or $ImmediateOffset -ge $Bytes.Length) {
        throw ("MajestyHD.exe is not the expected Steam build. Offset 0x{0:X} is out of range." -f $ImmediateOffset)
    }

    $opcode = $Bytes[$ImmediateOffset - 2]
    $modrm = $Bytes[$ImmediateOffset - 1]
    if ($opcode -ne 0x83 -or $modrm -notin @(0xF8, 0xE8, 0xC0, 0xC6, 0xED, 0xC5, 0xE9)) {
        throw ("MajestyHD.exe is not the expected Steam build near file offset 0x{0:X}." -f $ImmediateOffset)
    }
}

$outside = if ($OutsidePixels.HasValue) { $OutsidePixels.Value } else { [Math]::Min(127, $EdgePixels * 2) }
if ($outside -lt 1 -or $outside -gt 127) {
    throw "-OutsidePixels must be between 1 and 127."
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$backupDir = Join-Path $resolvedGamePath "_quest_map_edge_pan_originals"
$backupPath = Join-Path $backupDir "MajestyHD.exe.original"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$outsideNegativeByte = [byte](256 - $outside)
$outsidePositiveByte = [byte]$outside
$edgeByte = [byte]$EdgePixels

foreach ($offset in @($EdgeOffsets + $OutsideNegativeOffsets + $OutsidePositiveOffsets)) {
    Assert-InstructionShape $bytes $offset
}

Write-Host "Majesty Gold HD Wider Quest Map Edge Pan installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Edge pan zone: $EdgePixels pixels"
Write-Host "Outside tolerance: $outside pixels"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

foreach ($offset in $EdgeOffsets) {
    $status = if ($bytes[$offset] -eq $edgeByte) { "AlreadyPatched" } else { "WouldPatch" }
    if (-not $DryRun -and $status -eq "WouldPatch") {
        $status = "Patched"
    }
    Write-Host ("MajestyHD.exe: {0} edge threshold byte at file offset 0x{1:X} -> {2}" -f $status, $offset, $EdgePixels)
}
foreach ($offset in $OutsideNegativeOffsets) {
    $status = if ($bytes[$offset] -eq $outsideNegativeByte) { "AlreadyPatched" } else { "WouldPatch" }
    if (-not $DryRun -and $status -eq "WouldPatch") {
        $status = "Patched"
    }
    Write-Host ("MajestyHD.exe: {0} negative outside tolerance byte at file offset 0x{1:X} -> -{2}" -f $status, $offset, $outside)
}
foreach ($offset in $OutsidePositiveOffsets) {
    $status = if ($bytes[$offset] -eq $outsidePositiveByte) { "AlreadyPatched" } else { "WouldPatch" }
    if (-not $DryRun -and $status -eq "WouldPatch") {
        $status = "Patched"
    }
    Write-Host ("MajestyHD.exe: {0} positive outside tolerance byte at file offset 0x{1:X} -> +{2}" -f $status, $offset, $outside)
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete."
    return
}

Assert-FileWritable $exePath

if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}
if (-not (Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $exePath -Destination $backupPath
}

foreach ($offset in $EdgeOffsets) {
    $bytes[$offset] = $edgeByte
}
foreach ($offset in $OutsideNegativeOffsets) {
    $bytes[$offset] = $outsideNegativeByte
}
foreach ($offset in $OutsidePositiveOffsets) {
    $bytes[$offset] = $outsidePositiveByte
}

[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host ""
Write-Host "Done. The quest map edge-pan zone is now wider."
Write-Host "Use Uninstall - Restore Quest Map Edge Pan.bat to undo this patch."
