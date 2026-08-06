param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_suppress_message_flags_originals"
$PatchOffset = 0x48A90

[byte[]]$OriginalBytes = @(0x8B, 0x4C, 0x24, 0x10, 0x56, 0x57)
[byte[]]$PatchedBytes = @(0xC3, 0x90, 0x90, 0x90, 0x90, 0x90)

function Test-BytesEqual {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected)
    if ($Offset -lt 0 -or ($Offset + $Expected.Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Expected[$i]) { return $false }
    }
    return $true
}

function Get-MajestyPath {
    param([string]$RequestedPath)
    if ($RequestedPath) { return $RequestedPath }
    if (Test-Path -LiteralPath $DefaultGamePath) { return $DefaultGamePath }

    $appId = 73230
    $searched = New-Object System.Collections.Generic.List[string]
    $searched.Add($DefaultGamePath)
    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $installPath = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($installPath) { $steamRoots.Add($installPath) }
        } catch {}
    }

    $libraryRoots = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in $steamRoots) {
        $libraryRoots.Add($steamRoot)
        $libraryFile = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libraryFile) {
            foreach ($line in Get-Content -LiteralPath $libraryFile) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $libraryRoots.Add(($Matches[1] -replace '\\\\', '\'))
                }
            }
        }
    }

    foreach ($libraryRoot in ($libraryRoots | Select-Object -Unique)) {
        $candidate = Join-Path $libraryRoot "steamapps\common\Majesty HD"
        $searched.Add($candidate)
        if (Test-Path -LiteralPath $candidate) { return $candidate }

        $manifest = Join-Path $libraryRoot ("steamapps\appmanifest_" + $appId + ".acf")
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        foreach ($line in Get-Content -LiteralPath $manifest) {
            if ($line -match '"installdir"\s+"([^"]+)"') {
                $named = Join-Path $libraryRoot ("steamapps\common\" + ($Matches[1] -replace '\\\\', '\'))
                $searched.Add($named)
                if (Test-Path -LiteralPath $named) { return $named }
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
        throw "Cannot modify $(Split-Path -Leaf $Path). Close Majesty and try again. If needed, run the BAT as administrator."
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Save-PreInstallBackup {
    param([string]$SourcePath, [string]$BackupDir, [string]$BackupPath)
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    if (Test-Path -LiteralPath $BackupPath) { return }

    Copy-Item -LiteralPath $SourcePath -Destination $BackupPath
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $note = @"
MajestyHD.exe.before-suppress-message-flags

A copy of MajestyHD.exe taken immediately before Suppress All Message Flags was
first installed, on $stamp.

This is NOT guaranteed to be an unmodified executable. It may already include
other patches. The uninstaller never reads this file; it reverses only this
utility's own six bytes. Use Steam file verification for a guaranteed stock EXE.
"@
    Set-Content -LiteralPath (Join-Path $BackupDir "READ ME - what this file is.txt") -Value $note -Encoding ASCII
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
if (-not (Test-Path -LiteralPath $exePath)) { throw "Could not find MajestyHD.exe at $exePath." }

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$isStock = Test-BytesEqual $bytes $PatchOffset $OriginalBytes
$isPatched = Test-BytesEqual $bytes $PatchOffset $PatchedBytes
if (-not $isStock -and -not $isPatched) {
    throw ("Unexpected bytes in the message-flag constructor at file offset 0x{0:X}. This is not the expected Steam build, or another patch owns the same routine." -f $PatchOffset)
}

Write-Host "Majesty Gold HD Suppress All Message Flags installer"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($isPatched) {
    Write-Host "MajestyHD.exe: message flags are already suppressed."
    return
}
if ($DryRun) {
    Write-Host ("MajestyHD.exe: would patch the message-flag constructor at file offset 0x{0:X}." -f $PatchOffset)
    return
}

Assert-FileWritable $exePath
$backupDir = Join-Path $resolvedGamePath $BackupDirName
Save-PreInstallBackup $exePath $backupDir (Join-Path $backupDir "MajestyHD.exe.before-suppress-message-flags")
[Array]::Copy($PatchedBytes, 0, $bytes, $PatchOffset, $PatchedBytes.Length)
[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host "Done. Message icons, their sound, and forced mini-camera focus are suppressed."
Write-Host "Use Uninstall - Restore Message Flags.bat to restore stock behavior."

