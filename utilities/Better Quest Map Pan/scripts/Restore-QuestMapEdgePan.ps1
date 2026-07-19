param(
    [string]$GamePath = "",
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
        throw "Cannot restore MajestyHD.exe because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
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

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
foreach ($offset in @($EdgeOffsets + $OutsideNegativeOffsets + $OutsidePositiveOffsets)) {
    Assert-InstructionShape $bytes $offset
}

Write-Host "Majesty Gold HD Quest Map Edge Pan restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

foreach ($offset in $EdgeOffsets) {
    $status = if ($bytes[$offset] -eq 0x08) { "AlreadyStock" } else { "WouldRestore" }
    if (-not $DryRun -and $status -eq "WouldRestore") {
        $status = "Restored"
    }
    Write-Host ("MajestyHD.exe: {0} edge threshold byte at file offset 0x{1:X} -> 8" -f $status, $offset)
}
foreach ($offset in $OutsideNegativeOffsets) {
    $status = if ($bytes[$offset] -eq 0xF0) { "AlreadyStock" } else { "WouldRestore" }
    if (-not $DryRun -and $status -eq "WouldRestore") {
        $status = "Restored"
    }
    Write-Host ("MajestyHD.exe: {0} negative outside tolerance byte at file offset 0x{1:X} -> -16" -f $status, $offset)
}
foreach ($offset in $OutsidePositiveOffsets) {
    $status = if ($bytes[$offset] -eq 0x10) { "AlreadyStock" } else { "WouldRestore" }
    if (-not $DryRun -and $status -eq "WouldRestore") {
        $status = "Restored"
    }
    Write-Host ("MajestyHD.exe: {0} positive outside tolerance byte at file offset 0x{1:X} -> +16" -f $status, $offset)
}

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run complete."
    return
}

Assert-FileWritable $exePath

foreach ($offset in $EdgeOffsets) {
    $bytes[$offset] = 0x08
}
foreach ($offset in $OutsideNegativeOffsets) {
    $bytes[$offset] = 0xF0
}
foreach ($offset in $OutsidePositiveOffsets) {
    $bytes[$offset] = 0x10
}

[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host ""
Write-Host "Done. The quest map edge-pan zone is restored to stock."
