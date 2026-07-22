param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$PatchSectionName = ".mczp"

$ZoomConstructorCallVa = 0x5DDCC6
$ZoomConstructorCallOffset = 0x1DD0C6
$ZoomVtableEntryOffset = 0x348688
$ZoomRuntimeVtableEntryOffset = 0x33AC10

$OriginalConstructorCallBytes = [byte[]]@(0xE8, 0x45, 0xFC, 0xFF, 0xFF)
$OriginalVtableEntryBytes = [byte[]]@(0x10, 0xD9, 0x5D, 0x00)
$OriginalRuntimeVtableEntryBytes = [byte[]]@(0x10, 0xD9, 0x5D, 0x00)

function Read-U16 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
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
    $sectionAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 32)
    $sizeOfImageOffset = $optionalHeaderOffset + 56
    $sectionTableOffset = $optionalHeaderOffset + $optionalHeaderSize

    $sections = @()
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $off = $sectionTableOffset + ($i * 40)
        $nameBytes = $Bytes[$off..($off + 7)]
        $name = [Text.Encoding]::ASCII.GetString($nameBytes).TrimEnd([char]0)
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
        SectionAlignment = $sectionAlignment
        SizeOfImageOffset = $sizeOfImageOffset
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

function Write-Bytes {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Patch)

    for ($i = 0; $i -lt $Patch.Length; $i++) {
        $Bytes[$Offset + $i] = $Patch[$i]
    }
}

function Get-MajestyPath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        return $RequestedPath
    }
    if (Test-Path -LiteralPath $DefaultGamePath) {
        return $DefaultGamePath
    }
    throw "Could not find Majesty HD. Re-run with -GamePath ""C:\Path\To\Majesty HD""."
}

function Assert-FileWritable {
    param([string]$Path)

    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot patch MajestyHD.exe because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$pe = Get-PeInfo $bytes
$section = $pe.Sections | Where-Object { $_.Name -eq $PatchSectionName } | Select-Object -First 1

Write-Host "Majesty Gold HD Remember Camera Zoom restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if (-not $section) {
    Write-Host "MajestyHD.exe: Remember Camera Zoom is not installed."
    return
}

$patchVa = 0x400000 + $section.Rva
$constructorHook = New-RelativeCallBytes $ZoomConstructorCallVa ($patchVa + 0x100)
$vtableEntry = [BitConverter]::GetBytes([uint32]$patchVa)

$constructorIsPatched = Test-BytesEqual $bytes $ZoomConstructorCallOffset $constructorHook
$vtableIsPatched = Test-BytesEqual $bytes $ZoomVtableEntryOffset $vtableEntry
$runtimeVtableIsPatched = Test-BytesEqual $bytes $ZoomRuntimeVtableEntryOffset $vtableEntry

if (-not ($constructorIsPatched -or $vtableIsPatched -or $runtimeVtableIsPatched)) {
    Write-Host "MajestyHD.exe: no Remember Camera Zoom hooks are installed."
    return
}

if ($section.Index -ne ($pe.SectionCount - 1)) {
    throw ".mczp is not the last PE section. Refusing to remove it automatically."
}

$previousSection = $pe.Sections | Where-Object { $_.Index -eq ($section.Index - 1) } | Select-Object -First 1
$restoredFileSize = [int]$section.RawOffset
$restoredSizeOfImage = Align-Value ([uint32]($previousSection.Rva + [Math]::Max($previousSection.VirtualSize, $previousSection.RawSize))) ([uint32]$pe.SectionAlignment)

if ($DryRun) {
    if ($constructorIsPatched) {
        Write-Host ("MajestyHD.exe: would restore camera default-zoom call at file offset 0x{0:X}." -f $ZoomConstructorCallOffset)
    }
    if ($vtableIsPatched) {
        Write-Host ("MajestyHD.exe: would restore camera zoom vtable entry at file offset 0x{0:X}." -f $ZoomVtableEntryOffset)
    }
    if ($runtimeVtableIsPatched) {
        Write-Host ("MajestyHD.exe: would restore runtime camera zoom vtable entry at file offset 0x{0:X}." -f $ZoomRuntimeVtableEntryOffset)
    }
    Write-Host ("MajestyHD.exe: would remove .mczp section header at file offset 0x{0:X}." -f $section.HeaderOffset)
    Write-Host ("MajestyHD.exe: would truncate appended .mczp data back to file offset 0x{0:X}." -f $restoredFileSize)
    return
}

Assert-FileWritable $exePath

$restoredBytes = New-Object byte[] $restoredFileSize
[Array]::Copy($bytes, 0, $restoredBytes, 0, $restoredFileSize)

if ($constructorIsPatched) {
    Write-Bytes $restoredBytes $ZoomConstructorCallOffset $OriginalConstructorCallBytes
}
if ($vtableIsPatched) {
    Write-Bytes $restoredBytes $ZoomVtableEntryOffset $OriginalVtableEntryBytes
}
if ($runtimeVtableIsPatched) {
    Write-Bytes $restoredBytes $ZoomRuntimeVtableEntryOffset $OriginalRuntimeVtableEntryBytes
}

[BitConverter]::GetBytes([uint16]($pe.SectionCount - 1)).CopyTo($restoredBytes, $pe.SectionCountOffset)
[BitConverter]::GetBytes([uint32]$restoredSizeOfImage).CopyTo($restoredBytes, $pe.SizeOfImageOffset)
Write-Bytes $restoredBytes $section.HeaderOffset (New-Object byte[] 40)

[IO.File]::WriteAllBytes($exePath, $restoredBytes)

Write-Host "Done. Majesty's stock camera zoom behavior is restored."
