param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_quest_map_drag_originals"
$HookOffset = 0x79FB5
$CaveOffset = 0x334280

function Save-PreInstallBackup {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$BackupDir,
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$UtilityName
    )

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    if (Test-Path -LiteralPath $BackupPath) {
        return
    }

    Copy-Item -LiteralPath $SourcePath -Destination $BackupPath

    # Say plainly what this copy is. It is NOT a stock game file, and the
    # uninstaller never reads it: uninstalling reverses this utility's own byte
    # changes. Without this note the filename alone implies otherwise.
    $leaf = Split-Path -Leaf $BackupPath
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $note = @"
$leaf

A copy of MajestyHD.exe taken immediately before $UtilityName was first
installed, on $stamp.

This is NOT guaranteed to be an unmodified Majesty Gold HD executable. It is
whatever was on disk at that moment, which may already include other patches
you had installed.

You do not need this file to uninstall. The uninstaller reverses its own byte
changes and never reads this copy. It is kept only as a convenience snapshot.

For a guaranteed clean executable, use Steam instead:
  Right-click Majesty Gold HD > Properties > Installed Files >
  Verify integrity of game files
"@
    Set-Content -LiteralPath (Join-Path $BackupDir "READ ME - what this file is.txt") -Value $note -Encoding ASCII
}

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

    # Majesty Gold HD is Steam app 73230.
    $appId = 73230
    $searched = New-Object System.Collections.Generic.List[string]
    $searched.Add($DefaultGamePath)

    # Steam install roots from the registry.
    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $installPath = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($installPath) {
                $steamRoots.Add($installPath)
            }
        } catch {
        }
    }

    # Every Steam library, including the install roots themselves. A second
    # drive is the common case this exists for.
    $libraryRoots = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in $steamRoots) {
        $libraryRoots.Add($steamRoot)
        $libraryFile = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (-not (Test-Path -LiteralPath $libraryFile)) {
            continue
        }
        foreach ($line in Get-Content -LiteralPath $libraryFile) {
            if ($line -match '"path"\s+"([^"]+)"') {
                $libraryRoots.Add(($Matches[1] -replace '\\\\', '\'))
            }
        }
    }

    foreach ($libraryRoot in ($libraryRoots | Select-Object -Unique)) {
        $candidate = Join-Path $libraryRoot "steamapps\common\Majesty HD"
        $searched.Add($candidate)
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }

        # The install folder can be named something else. Ask Steam's own
        # manifest rather than assuming.
        $manifest = Join-Path $libraryRoot ("steamapps\appmanifest_" + $appId + ".acf")
        if (-not (Test-Path -LiteralPath $manifest)) {
            continue
        }
        foreach ($line in Get-Content -LiteralPath $manifest) {
            if ($line -match '"installdir"\s+"([^"]+)"') {
                $named = Join-Path $libraryRoot ("steamapps\common\" + ($Matches[1] -replace '\\\\', '\'))
                $searched.Add($named)
                if (Test-Path -LiteralPath $named) {
                    return $named
                }
            }
        }
    }

    $lines = ($searched | Select-Object -Unique | ForEach-Object { "  $_" }) -join [Environment]::NewLine
    throw (
        "Could not find Majesty Gold HD." + [Environment]::NewLine +
        "Looked in:" + [Environment]::NewLine + $lines + [Environment]::NewLine +
        'Re-run with -GamePath "D:\Path\To\Majesty HD".'
    )
}

function Assert-FileWritable {
    param([string]$Path)

    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        $name = Split-Path -Leaf $Path
        throw "Cannot modify $name because it is in use or not writable. Close Majesty Gold HD and try again. If the game is already closed, right-click the BAT and choose Run as administrator."
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

function Test-ZeroRange {
    param([byte[]]$Bytes, [int]$Offset, [int]$Length)

    if ($Offset -lt 0 -or ($Offset + $Length) -gt $Bytes.Length) {
        return $false
    }
    for ($i = 0; $i -lt $Length; $i++) {
        if ($Bytes[$Offset + $i] -ne 0) {
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

$hookAlreadyPatched = Test-BytesEqual $bytes $HookOffset $HookBytes
$hookIsStock = Test-BytesEqual $bytes $HookOffset $OriginalHookBytes
$stubAlreadyPatched = Test-BytesEqual $bytes $CaveOffset $StubBytes
$stubIsEmpty = Test-ZeroRange $bytes $CaveOffset $StubBytes.Length

if (-not $hookAlreadyPatched -and -not $hookIsStock) {
    throw ("MajestyHD.exe is not the expected Steam build near file offset 0x{0:X}, or another patch already owns this hook." -f $HookOffset)
}
if (-not $stubAlreadyPatched -and -not $stubIsEmpty) {
    throw ("The click-drag code-cave range at file offset 0x{0:X} is not empty. Refusing to overwrite it." -f $CaveOffset)
}

Write-Host "Majesty Gold HD Quest Map Drag installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "This lets you hold the left mouse button on the quest map and drag to pan."
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($hookAlreadyPatched -and $stubAlreadyPatched) {
    Write-Host "MajestyHD.exe: click-drag panning is already installed."
    return
}

if ($DryRun) {
    Write-Host ("MajestyHD.exe: would patch hook at file offset 0x{0:X}." -f $HookOffset)
    Write-Host ("MajestyHD.exe: would write click-drag stub at file offset 0x{0:X}." -f $CaveOffset)
    return
}

Assert-FileWritable $exePath

# This utility previously wrote no backup at all, unlike the others. Kept for
# consistency; the uninstaller still works purely by reversing its own bytes.
Save-PreInstallBackup $exePath (Join-Path $resolvedGamePath $BackupDirName) `
    (Join-Path (Join-Path $resolvedGamePath $BackupDirName) "MajestyHD.exe.before-quest-map-drag") `
    "Quest Map Drag"

for ($i = 0; $i -lt $HookBytes.Length; $i++) {
    $bytes[$HookOffset + $i] = $HookBytes[$i]
}
for ($i = 0; $i -lt $StubBytes.Length; $i++) {
    $bytes[$CaveOffset + $i] = $StubBytes[$i]
}

[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host "Done. Click-drag quest map panning is installed."
Write-Host "Use Uninstall - Restore Stock Quest Map.bat to remove click-drag panning."
