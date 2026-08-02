param(
    [string]$GamePath = ""
)

$ErrorActionPreference = "Stop"
$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"

# This utility makes exactly two 4-byte edits to MajestyHD.exe. They are undone
# by writing the stock values back, never by restoring a whole-file backup.
#
# Restoring the whole executable would revert every other patch installed since,
# silently: Quest Map Drag, Remember Active Mods, Remember Game Speed, Remember
# Camera Zoom and the Speedrun Timer all write to the same file. Inside the QoL
# bundle that damage was hidden because this uninstaller runs late, after the
# others are already removed. Run standalone, it destroyed all of them.
$FreestyleIconCallbackOffset = 0x798B6
$CustomQuestCompareImmediateOffset = 0x7A0FE
$FreestyleCallbackBytes = [byte[]](0x00, 0x93, 0x47, 0x00)     # stock
$CustomQuestCallbackBytes = [byte[]](0x00, 0x92, 0x47, 0x00)   # patched
$CustomQuestObjectBytes = [byte[]](0xC2, 0x0F, 0x00, 0x00)     # stock
$FreestyleObjectBytes = [byte[]](0x88, 0x13, 0x00, 0x00)       # patched

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

$resolvedGamePath = Get-MajestyPath $GamePath
$dataPath = Join-Path $resolvedGamePath "Data"
$backupDir = Join-Path $dataPath "_custom_quest_button_originals"
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"

Write-Host "Majesty Gold HD Custom Quest Button restore"
Write-Host "Game path: $resolvedGamePath"
Write-Host ""

if (-not (Test-Path -LiteralPath $backupDir)) {
    throw "No backup folder found at $backupDir."
}

$backups = Get-ChildItem -LiteralPath $backupDir -Filter "UIData_*.dat.original" | Sort-Object Name
if ($backups.Count -eq 0) {
    throw "No UIData backups found in $backupDir."
}

# The exe is repaired by reversing our own two edits, so no backup is required.
$exeNeedsRestore = $false
if (Test-Path -LiteralPath $exePath) {
    [byte[]]$exeBytes = [IO.File]::ReadAllBytes($exePath)
    foreach ($hook in @(
        @{ Offset = $FreestyleIconCallbackOffset; Stock = $FreestyleCallbackBytes; Patched = $CustomQuestCallbackBytes; Name = "Freestyle icon hover callback" },
        @{ Offset = $CustomQuestCompareImmediateOffset; Stock = $CustomQuestObjectBytes; Patched = $FreestyleObjectBytes; Name = "Custom Quest click compare" }
    )) {
        $isStock = Test-BytesEqual $exeBytes $hook.Offset $hook.Stock
        $isPatched = Test-BytesEqual $exeBytes $hook.Offset $hook.Patched
        if (-not $isStock -and -not $isPatched) {
            $found = [BitConverter]::ToString($exeBytes, $hook.Offset, 4)
            throw ("MajestyHD.exe has unexpected bytes at file offset 0x{0:X} for {1}. Found {2}. Refusing to modify it." -f $hook.Offset, $hook.Name, $found)
        }
        if ($isPatched) {
            $exeNeedsRestore = $true
        }
    }
}

$targets = foreach ($backup in $backups) {
    $fileName = $backup.Name -replace "\.original$", ""
    Join-Path $dataPath $fileName
}

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target)) {
        continue
    }

    $stream = $null
    try {
        $stream = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        $name = Split-Path -Leaf $target
        throw "Cannot restore $name because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

if ($exeNeedsRestore) {
    $stream = $null
    try {
        $stream = [IO.File]::Open($exePath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot restore MajestyHD.exe because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

foreach ($backup in $backups) {
    $fileName = $backup.Name -replace "\.original$", ""
    $target = Join-Path $dataPath $fileName
    Copy-Item -LiteralPath $backup.FullName -Destination $target -Force
    Write-Host "${fileName}: restored"
}

if ($exeNeedsRestore) {
    # Reverse only our own two edits. Never copy a whole backup over the
    # executable: other utilities patch the same file and would be wiped.
    [byte[]]$exeBytes = [IO.File]::ReadAllBytes($exePath)
    foreach ($hook in @(
        @{ Offset = $FreestyleIconCallbackOffset; Stock = $FreestyleCallbackBytes; Patched = $CustomQuestCallbackBytes; Name = "Freestyle icon hover callback" },
        @{ Offset = $CustomQuestCompareImmediateOffset; Stock = $CustomQuestObjectBytes; Patched = $FreestyleObjectBytes; Name = "Custom Quest click compare" }
    )) {
        if (Test-BytesEqual $exeBytes $hook.Offset $hook.Patched) {
            [Array]::Copy($hook.Stock, 0, $exeBytes, $hook.Offset, $hook.Stock.Length)
            Write-Host ("MajestyHD.exe: restored {0} at file offset 0x{1:X}" -f $hook.Name, $hook.Offset)
        }
    }
    [IO.File]::WriteAllBytes($exePath, $exeBytes)
} else {
    Write-Host "MajestyHD.exe: already stock for this utility."
}

Write-Host ""
Write-Host "Done. Other utilities that patch MajestyHD.exe were left untouched."
