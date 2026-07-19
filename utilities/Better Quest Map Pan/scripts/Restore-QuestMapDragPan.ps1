param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$HookOffset = 0x79FB5
$CaveOffset = 0x334280

[byte[]]$OriginalHookBytes = @(0x8B, 0x44, 0x24, 0x40, 0x8B, 0x4C, 0x24, 0x20)
[byte[]]$HookBytes = @(0xE9, 0xC6, 0xA2, 0x2B, 0x00, 0x90, 0x90, 0x90)
[byte[]]$StubBytes = @(
    0x60, 0x6A, 0x01, 0xFF, 0x15, 0x7C, 0x54, 0x73, 0x00, 0x66, 0xA9, 0x00, 0x80, 0x0F, 0x84, 0x8B,
    0x00, 0x00, 0x00, 0x8B, 0x74, 0x24, 0x0C, 0x68, 0xEC, 0x25, 0x7C, 0x00, 0x68, 0xE8, 0x25, 0x7C,
    0x00, 0xE8, 0xCA, 0x04, 0xF0, 0xFF, 0x83, 0xC4, 0x08, 0xA1, 0xE8, 0x25, 0x7C, 0x00, 0x3B, 0x46,
    0x74, 0x7C, 0x6B, 0x3B, 0x46, 0x7C, 0x7F, 0x66, 0xA1, 0xEC, 0x25, 0x7C, 0x00, 0x3B, 0x46, 0x78,
    0x7C, 0x5C, 0x3B, 0x86, 0x80, 0x00, 0x00, 0x00, 0x7F, 0x54, 0x81, 0x3D, 0xE0, 0x25, 0x7C, 0x00,
    0x44, 0x52, 0x41, 0x47, 0x75, 0x1C, 0xA1, 0xE4, 0x25, 0x7C, 0x00, 0x2B, 0x05, 0xE8, 0x25, 0x7C,
    0x00, 0x01, 0x46, 0x40, 0xA1, 0xF0, 0x25, 0x7C, 0x00, 0x2B, 0x05, 0xEC, 0x25, 0x7C, 0x00, 0x01,
    0x46, 0x20, 0xA1, 0xE8, 0x25, 0x7C, 0x00, 0xA3, 0xE4, 0x25, 0x7C, 0x00, 0xA1, 0xEC, 0x25, 0x7C,
    0x00, 0xA3, 0xF0, 0x25, 0x7C, 0x00, 0xC7, 0x05, 0xE0, 0x25, 0x7C, 0x00, 0x44, 0x52, 0x41, 0x47,
    0x61, 0x8B, 0x44, 0x24, 0x40, 0x8B, 0x4C, 0x24, 0x20, 0xE9, 0x9F, 0x5C, 0xD4, 0xFF, 0xC7, 0x05,
    0xE0, 0x25, 0x7C, 0x00, 0x00, 0x00, 0x00, 0x00, 0xEB, 0xE6
)

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
        throw "Cannot restore MajestyHD.exe because it is in use or not writable. Close Majesty Gold HD and run this uninstaller again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Test-BytesEqual {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected)

    if ($Offset -lt 0 -or ($Offset + $Expected.Length) -gt $Bytes.Length) {
        return $false
    }

    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Expected[$i]) {
            return $false
        }
    }
    return $true
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$hookIsPatched = Test-BytesEqual $bytes $HookOffset $HookBytes
$hookIsStock = Test-BytesEqual $bytes $HookOffset $OriginalHookBytes
$stubIsPatched = Test-BytesEqual $bytes $CaveOffset $StubBytes

Write-Host "Majesty Gold HD Click-Drag Quest Map Pan restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($hookIsStock -and -not $stubIsPatched) {
    Write-Host "MajestyHD.exe: click-drag panning is not installed."
    return
}

if (-not $hookIsPatched) {
    throw ("MajestyHD.exe does not contain this click-drag hook at file offset 0x{0:X}. Refusing to restore." -f $HookOffset)
}
if (-not $stubIsPatched) {
    throw ("MajestyHD.exe does not contain this click-drag stub at file offset 0x{0:X}. Refusing to restore." -f $CaveOffset)
}

if ($DryRun) {
    Write-Host ("MajestyHD.exe: would restore hook at file offset 0x{0:X}." -f $HookOffset)
    Write-Host ("MajestyHD.exe: would clear click-drag stub at file offset 0x{0:X}." -f $CaveOffset)
    return
}

Assert-FileWritable $exePath

for ($i = 0; $i -lt $OriginalHookBytes.Length; $i++) {
    $bytes[$HookOffset + $i] = $OriginalHookBytes[$i]
}
for ($i = 0; $i -lt $StubBytes.Length; $i++) {
    $bytes[$CaveOffset + $i] = 0
}

[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host "Done. Click-drag quest map panning has been removed."
