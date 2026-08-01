param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_remember_camera_zoom_originals"

# PE section characteristics: code, execute, read, write. The section holds runtime scratch state.
$SectionCharacteristics = 3758096416  # 0xE0000020: code, execute, read, write

$PatchSectionName = ".mczp"
$PatchRawSize = 0x1000
$PatchVirtualSize = 0x800

$ZoomConstructorCallVa = 0x5DDCC6
$ZoomConstructorCallOffset = 0x1DD0C6
$ZoomVtableEntryVa = 0x749288
$ZoomVtableEntryOffset = 0x348688
$ZoomRuntimeVtableEntryVa = 0x73B810
$ZoomRuntimeVtableEntryOffset = 0x33AC10
$ZoomSetterVa = 0x5DD910

$OriginalConstructorCallBytes = [byte[]]@(0xE8, 0x45, 0xFC, 0xFF, 0xFF)
$OriginalVtableEntryBytes = [byte[]]@(0x10, 0xD9, 0x5D, 0x00)
$OriginalRuntimeVtableEntryBytes = [byte[]]@(0x10, 0xD9, 0x5D, 0x00)

$FopenIat = 0x735430
$FreadIat = 0x735434
$FwriteIat = 0x735438
$FcloseIat = 0x735444

function Read-U16 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

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

function Align-Value {
    param([uint32]$Value, [uint32]$Alignment)
    return [uint32](([uint64]([Math]::Ceiling([double]$Value / [double]$Alignment))) * [uint64]$Alignment)
}

function Get-PeInfo {
    param([byte[]]$Bytes)

    $peOffset = Read-U32 $Bytes 0x3C
    $sectionCountOffset = $peOffset + 6
    $sectionCount = Read-U16 $Bytes $sectionCountOffset
    $optionalHeaderSize = Read-U16 $Bytes ($peOffset + 20)
    $optionalHeaderOffset = $peOffset + 24
    $sectionTableOffset = $optionalHeaderOffset + $optionalHeaderSize

    $sections = @()
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $off = $sectionTableOffset + ($i * 40)
        $name = [Text.Encoding]::ASCII.GetString($Bytes[$off..($off + 7)]).TrimEnd([char]0)
        $sections += [pscustomobject]@{
            Index = $i
            HeaderOffset = $off
            Name = $name
            VirtualSize = Read-U32 $Bytes ($off + 8)
            Rva = Read-U32 $Bytes ($off + 12)
            RawSize = Read-U32 $Bytes ($off + 16)
            RawOffset = Read-U32 $Bytes ($off + 20)
        }
    }

    return [pscustomobject]@{
        SectionCountOffset = $sectionCountOffset
        SectionCount = $sectionCount
        ImageBase = Read-U32 $Bytes ($optionalHeaderOffset + 28)
        SectionAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 32)
        FileAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 36)
        SizeOfImageOffset = $optionalHeaderOffset + 56
        SizeOfImage = Read-U32 $Bytes ($optionalHeaderOffset + 56)
        SizeOfHeaders = Read-U32 $Bytes ($optionalHeaderOffset + 60)
        SectionTableOffset = $sectionTableOffset
        Sections = $sections
    }
}

function New-RelativeCallBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE8
    [BitConverter]::GetBytes($relative).CopyTo($result, 1)
    return $result
}

function New-RelativeJumpBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE9
    [BitConverter]::GetBytes($relative).CopyTo($result, 1)
    return $result
}

function New-SectionHeader {
    param(
        [string]$Name,
        [uint32]$VirtualSize,
        [uint32]$Rva,
        [uint32]$RawSize,
        [uint32]$RawOffset
    )

    $bytes = New-Object byte[] 40
    [Text.Encoding]::ASCII.GetBytes($Name).CopyTo($bytes, 0)
    [BitConverter]::GetBytes($VirtualSize).CopyTo($bytes, 8)
    [BitConverter]::GetBytes($Rva).CopyTo($bytes, 12)
    [BitConverter]::GetBytes($RawSize).CopyTo($bytes, 16)
    [BitConverter]::GetBytes($RawOffset).CopyTo($bytes, 20)
    [BitConverter]::GetBytes([uint32]$SectionCharacteristics).CopyTo($bytes, 36)
    return $bytes
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

function Write-Bytes {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Patch)

    # A null or empty patch means the caller built the wrong thing. PowerShell
    # evaluates $null.Length to $null, so the loop below would silently write
    # nothing, leaving a hooked-but-empty code section and a game that jumps
    # into blank memory. Fail loudly instead of shipping a broken exe.
    if ($null -eq $Patch -or $Patch.Length -eq 0) {
        throw ("Write-Bytes received no data for file offset 0x{0:X}. This is an installer bug, not a problem with your game files." -f $Offset)
    }
    if ($Offset -lt 0 -or ($Offset + $Patch.Length) -gt $Bytes.Length) {
        throw ("Write-Bytes range 0x{0:X}..0x{1:X} falls outside the {2}-byte image." -f $Offset, ($Offset + $Patch.Length - 1), $Bytes.Length)
    }

    for ($i = 0; $i -lt $Patch.Length; $i++) {
        $Bytes[$Offset + $i] = $Patch[$i]
    }
}

function New-UInt32Bytes {
    param([uint32]$Value)
    return [BitConverter]::GetBytes($Value)
}

function New-PatchBlob {
    param(
        [uint32]$PatchVa,
        [Parameter(Mandatory = $true)][string]$PreferencePath
    )

    $bytes = New-Object byte[] $PatchRawSize
    $saveZoomVa = $PatchVa
    $restoreZoomVa = $PatchVa + 0x100
    # The preference path used to be the bare filename "MajestyCameraZoom.bin",
    # which fopen resolves against the process working directory. For a Steam
    # launch that is the game folder under Program Files, which a standard user
    # cannot write, so the setting silently never persisted. Remember Game Speed
    # already had this fixed; the fix was never carried across.
    #
    # An absolute path needs more room than the old 0x40-byte slot at 0x500, so
    # the string moved to 0x600 where 0x200 bytes are free below the 0x800
    # virtual size.
    $fileNameVa = $PatchVa + 0x600
    $wbVa = $PatchVa + 0x540
    $rbVa = $PatchVa + 0x543
    $zoomTempVa = $PatchVa + 0x700

    if ([Text.Encoding]::ASCII.GetByteCount($PreferencePath) -ge 0x100) {
        throw "The Remember Camera Zoom preference path is too long to embed safely: $PreferencePath"
    }

    function Set-Bytes {
        param([int]$Offset, [byte[]]$Patch)
        for ($i = 0; $i -lt $Patch.Length; $i++) {
            $bytes[$Offset + $i] = $Patch[$i]
        }
    }

    function Set-UInt32 {
        param([int]$Offset, [uint32]$Value)
        [BitConverter]::GetBytes($Value).CopyTo($bytes, $Offset)
    }

    function Set-AsciiZ {
        param([int]$Offset, [string]$Text)
        $raw = [Text.Encoding]::ASCII.GetBytes($Text)
        Set-Bytes $Offset $raw
        $bytes[$Offset + $raw.Length] = 0
    }

    [byte[]]$saveZoom = @(
        0x60,
        0x8B, 0x44, 0x24, 0x24,
        0xA3, 0, 0, 0, 0,
        0x68, 0, 0, 0, 0,
        0x68, 0, 0, 0, 0,
        0xFF, 0x15, 0, 0, 0, 0,
        0x83, 0xC4, 0x08,
        0x85, 0xC0,
        0x74, 0x1F,
        0x89, 0xC3,
        0x53,
        0x6A, 0x01,
        0x6A, 0x04,
        0x68, 0, 0, 0, 0,
        0xFF, 0x15, 0, 0, 0, 0,
        0x83, 0xC4, 0x10,
        0x53,
        0xFF, 0x15, 0, 0, 0, 0,
        0x83, 0xC4, 0x04,
        0x61,
        0xE9, 0, 0, 0, 0
    )
    Set-Bytes 0x000 $saveZoom
    Set-UInt32 0x006 $zoomTempVa
    Set-UInt32 0x00B $wbVa
    Set-UInt32 0x010 $fileNameVa
    Set-UInt32 0x016 $FopenIat
    Set-UInt32 0x029 $zoomTempVa
    Set-UInt32 0x02F $FwriteIat
    Set-UInt32 0x039 $FcloseIat
    (New-RelativeJumpBytes ($saveZoomVa + 0x041) $ZoomSetterVa).CopyTo($bytes, 0x041)

    [byte[]]$restoreZoom = @(
        0x60,
        0x68, 0, 0, 0, 0,
        0x68, 0, 0, 0, 0,
        0xFF, 0x15, 0, 0, 0, 0,
        0x83, 0xC4, 0x08,
        0x85, 0xC0,
        0x74, 0x43,
        0x89, 0xC3,
        0x53,
        0x6A, 0x01,
        0x6A, 0x04,
        0x68, 0, 0, 0, 0,
        0xFF, 0x15, 0, 0, 0, 0,
        0x83, 0xC4, 0x10,
        0x89, 0xC6,
        0x53,
        0xFF, 0x15, 0, 0, 0, 0,
        0x83, 0xC4, 0x04,
        0x85, 0xF6,
        0x74, 0x1E,
        0x8B, 0x05, 0, 0, 0, 0,
        0x3D, 0x00, 0x00, 0x00, 0x3F,
        0x72, 0x11,
        0x3D, 0x00, 0x00, 0x40, 0x40,
        0x77, 0x0A,
        0x89, 0x44, 0x24, 0x24,
        0x61,
        0xE9, 0, 0, 0, 0,
        0x61,
        0xE9, 0, 0, 0, 0
    )
    Set-Bytes 0x100 $restoreZoom
    Set-UInt32 0x102 $rbVa
    Set-UInt32 0x107 $fileNameVa
    Set-UInt32 0x10D $FopenIat
    Set-UInt32 0x120 $zoomTempVa
    Set-UInt32 0x126 $FreadIat
    Set-UInt32 0x132 $FcloseIat
    Set-UInt32 0x13F $zoomTempVa
    (New-RelativeJumpBytes ($restoreZoomVa + 0x56) $ZoomSetterVa).CopyTo($bytes, 0x156)
    (New-RelativeJumpBytes ($restoreZoomVa + 0x5C) $ZoomSetterVa).CopyTo($bytes, 0x15C)

    Set-AsciiZ 0x600 $PreferencePath
    Set-AsciiZ 0x540 "wb"
    Set-AsciiZ 0x543 "rb"

    return $bytes
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

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$backupDir = Join-Path $resolvedGamePath $BackupDirName
$backupPath = Join-Path $backupDir "MajestyHD.exe.before-remember-camera-zoom"
$preferenceDir = Join-Path (
    [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
) "MajestyHD"
$preferencePath = Join-Path $preferenceDir "MajestyCameraZoom.bin"
$legacyPreferencePath = Join-Path $resolvedGamePath "MajestyCameraZoom.bin"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$pe = Get-PeInfo $bytes
$existingSection = $pe.Sections | Where-Object { $_.Name -eq $PatchSectionName } | Select-Object -First 1

if ($existingSection) {
    $patchSectionRva = [uint32]$existingSection.Rva
    $patchSectionRawOffset = [uint32]$existingSection.RawOffset
    $patchSectionVa = [uint32]($pe.ImageBase + $patchSectionRva)
    $patchSectionHeaderOffset = [int]$existingSection.HeaderOffset
    $patchSectionHeader = New-SectionHeader $PatchSectionName $PatchVirtualSize $patchSectionRva $PatchRawSize $patchSectionRawOffset
    $patchedFileSize = [int]($patchSectionRawOffset + $PatchRawSize)
} else {
    $lastSection = $pe.Sections | Sort-Object RawOffset | Select-Object -Last 1
    $patchSectionRawOffset = Align-Value ([uint32]$bytes.Length) ([uint32]$pe.FileAlignment)
    $lastVirtualEnd = [uint32]($lastSection.Rva + [Math]::Max($lastSection.VirtualSize, $lastSection.RawSize))
    $patchSectionRva = Align-Value $lastVirtualEnd ([uint32]$pe.SectionAlignment)
    $patchSectionVa = [uint32]($pe.ImageBase + $patchSectionRva)
    $patchSectionHeaderOffset = [int]($pe.SectionTableOffset + ($pe.SectionCount * 40))
    $patchSectionHeader = New-SectionHeader $PatchSectionName $PatchVirtualSize $patchSectionRva $PatchRawSize $patchSectionRawOffset
    $patchedFileSize = [int]($patchSectionRawOffset + $PatchRawSize)

    if (($patchSectionHeaderOffset + 40) -gt $pe.SizeOfHeaders) {
        throw "No room remains in the PE header for another patch section."
    }
    if (-not (Test-ZeroRange $bytes $patchSectionHeaderOffset 40)) {
        throw ("The PE header slot at file offset 0x{0:X} is not empty. Refusing to add a patch section." -f $patchSectionHeaderOffset)
    }
    if ($patchSectionRawOffset -ne $bytes.Length) {
        throw ("MajestyHD.exe has unaligned trailing data. Expected new section at 0x{0:X}, but file ends at 0x{1:X}." -f $patchSectionRawOffset, $bytes.Length)
    }
}

$patchBlob = New-PatchBlob $patchSectionVa $preferencePath
$newConstructorHook = New-RelativeCallBytes $ZoomConstructorCallVa ($patchSectionVa + 0x100)
$newVtableEntry = New-UInt32Bytes $patchSectionVa

$constructorIsStock = Test-BytesEqual $bytes $ZoomConstructorCallOffset $OriginalConstructorCallBytes
$constructorAlreadyPatched = Test-BytesEqual $bytes $ZoomConstructorCallOffset $newConstructorHook
$vtableIsStock = Test-BytesEqual $bytes $ZoomVtableEntryOffset $OriginalVtableEntryBytes
$vtableAlreadyPatched = Test-BytesEqual $bytes $ZoomVtableEntryOffset $newVtableEntry
$runtimeVtableIsStock = Test-BytesEqual $bytes $ZoomRuntimeVtableEntryOffset $OriginalRuntimeVtableEntryBytes
$runtimeVtableAlreadyPatched = Test-BytesEqual $bytes $ZoomRuntimeVtableEntryOffset $newVtableEntry
$headerAlreadyPatched = $existingSection -and (Test-BytesEqual $bytes $patchSectionHeaderOffset $patchSectionHeader)
$blobAlreadyPatched = $existingSection -and (Test-BytesEqual $bytes $patchSectionRawOffset $patchBlob)

if (-not ($constructorIsStock -or $constructorAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the camera constructor hook 0x{0:X}." -f $ZoomConstructorCallOffset)
}
if (-not ($vtableIsStock -or $vtableAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the camera zoom vtable entry 0x{0:X}." -f $ZoomVtableEntryOffset)
}
if (-not ($runtimeVtableIsStock -or $runtimeVtableAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the runtime camera zoom vtable entry 0x{0:X}." -f $ZoomRuntimeVtableEntryOffset)
}
if ($existingSection -and $bytes.Length -lt $patchedFileSize) {
    throw ("MajestyHD.exe has a .mczp header but is too short: 0x{0:X}, expected at least 0x{1:X}." -f $bytes.Length, $patchedFileSize)
}

$newSizeOfImage = Align-Value ([uint32]($patchSectionRva + $PatchVirtualSize)) ([uint32]$pe.SectionAlignment)

Write-Host "Majesty Gold HD Remember Camera Zoom installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Preset file: $preferencePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($existingSection -and $headerAlreadyPatched -and $constructorAlreadyPatched -and $vtableAlreadyPatched -and $runtimeVtableAlreadyPatched -and $blobAlreadyPatched) {
    Write-Host "MajestyHD.exe: Remember Camera Zoom is already installed."
    return
}

if ($DryRun) {
    if (-not $existingSection) {
        Write-Host ("MajestyHD.exe: would add .mczp section header at file offset 0x{0:X}." -f $patchSectionHeaderOffset)
        Write-Host ("MajestyHD.exe: would append .mczp section data at file offset 0x{0:X}." -f $patchSectionRawOffset)
    } else {
        Write-Host ("MajestyHD.exe: would update .mczp section data at file offset 0x{0:X}." -f $patchSectionRawOffset)
    }
    if (-not $constructorAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch camera default-zoom restore call at file offset 0x{0:X}." -f $ZoomConstructorCallOffset)
    }
    if (-not $vtableAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch camera zoom setter vtable entry at file offset 0x{0:X}." -f $ZoomVtableEntryOffset)
    }
    if (-not $runtimeVtableAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch runtime camera zoom setter vtable entry at file offset 0x{0:X}." -f $ZoomRuntimeVtableEntryOffset)
    }
    return
}

Assert-FileWritable $exePath

if (-not (Test-Path -LiteralPath $preferenceDir)) {
    New-Item -ItemType Directory -Path $preferenceDir | Out-Null
}
# Carry across a setting saved by an older build that wrote into the game folder.
if (
    (-not (Test-Path -LiteralPath $preferencePath)) -and
    (Test-Path -LiteralPath $legacyPreferencePath)
) {
    Copy-Item -LiteralPath $legacyPreferencePath -Destination $preferencePath
}

Save-PreInstallBackup $exePath $backupDir $backupPath "Remember Camera Zoom"

# Keep the file's existing length when updating in place. $patchedFileSize is
# only where OUR section ends, and another utility's section may sit after it,
# making the file longer. Sizing the buffer to $patchedFileSize then threw
# "Destination array was not long enough" on every re-install where .mczp was
# not the last section.
$targetFileSize = if ($existingSection) { $bytes.Length } else { $patchedFileSize }
$patchedBytes = New-Object byte[] $targetFileSize
[Array]::Copy($bytes, 0, $patchedBytes, 0, $bytes.Length)

if (-not $existingSection) {
    [BitConverter]::GetBytes([uint16]($pe.SectionCount + 1)).CopyTo($patchedBytes, $pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$newSizeOfImage).CopyTo($patchedBytes, $pe.SizeOfImageOffset)
}
Write-Bytes $patchedBytes $patchSectionHeaderOffset $patchSectionHeader
Write-Bytes $patchedBytes $patchSectionRawOffset $patchBlob
Write-Bytes $patchedBytes $ZoomConstructorCallOffset $newConstructorHook
Write-Bytes $patchedBytes $ZoomVtableEntryOffset $newVtableEntry
Write-Bytes $patchedBytes $ZoomRuntimeVtableEntryOffset $newVtableEntry

[IO.File]::WriteAllBytes($exePath, $patchedBytes)

Write-Host "Done. Majesty should now remember the in-quest camera zoom."
