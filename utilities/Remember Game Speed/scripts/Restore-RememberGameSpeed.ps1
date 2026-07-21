param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$PatchSectionName = ".mskp"

$SpeedSliderSaveOffset = 0x6A318
$SpeedRestoreOneOffset = 0xD84F9
$SpeedRestoreTwoOffset = 0xD8F4A
$SpeedCopyOneOffset = 0x694C4
$SpeedCopyTwoOffset = 0x69609
$SpeedObjectInitOneOffset = 0x841D2
$SpeedObjectInitTwoOffset = 0x28406
$SpeedObjectInitThreeOffset = 0x28419
$OldOptionsSaveOffset = 0x875F0
$OldOptionsRestoreOffset = 0x72E8D

$OriginalSliderSaveBytes = [byte[]]@(0xA3, 0x04, 0x53, 0x7B, 0x00)
$OriginalSpeedWriteBytes = [byte[]]@(0x89, 0x0D, 0x04, 0x53, 0x7B, 0x00)
$OriginalSpeedWriteEdxBytes = [byte[]]@(0x89, 0x15, 0x04, 0x53, 0x7B, 0x00)
$OriginalSpeedWriteEbxObjectBytes = [byte[]]@(0x89, 0x98, 0x98, 0x00, 0x00, 0x00)
$OriginalSpeedWriteEsiObjectBytes = [byte[]]@(0x89, 0xB0, 0x98, 0x00, 0x00, 0x00)
$OriginalOptionsSaveBytes = [byte[]]@(0x6A, 0xFF, 0x68, 0xAB, 0xEF, 0x6E, 0x00)
$OriginalOptionsRestoreBytes = [byte[]]@(0xE8, 0xAE, 0x19, 0x08, 0x00)

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

function New-RelativeJumpBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE9
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

Write-Host "Majesty Gold HD Remember Game Speed restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if (-not $section) {
    Write-Host "MajestyHD.exe: Remember Game Speed is not installed."
    return
}

$patchVa = 0x400000 + $section.Rva
$sliderHook = New-RelativeJumpBytes 0x46AF18 $patchVa
$restoreOneHook = New-RelativeJumpBytes 0x4D90F9 ($patchVa + 0x100)
$restoreOneHook += [byte[]]@(0x90)
$restoreTwoHook = New-RelativeJumpBytes 0x4D9B4A ($patchVa + 0x240)
$restoreTwoHook += [byte[]]@(0x90)
$copyOneHook = New-RelativeJumpBytes 0x46A0C4 ($patchVa + 0x340)
$copyOneHook += [byte[]]@(0x90)
$copyTwoHook = New-RelativeJumpBytes 0x46A209 ($patchVa + 0x380)
$copyTwoHook += [byte[]]@(0x90)
$objectInitOneHook = New-RelativeJumpBytes 0x484DD2 ($patchVa + 0x3C0)
$objectInitOneHook += [byte[]]@(0x90)
$objectInitTwoHook = New-RelativeJumpBytes 0x429006 ($patchVa + 0x400)
$objectInitTwoHook += [byte[]]@(0x90)
$objectInitThreeHook = New-RelativeJumpBytes 0x429019 ($patchVa + 0x440)
$objectInitThreeHook += [byte[]]@(0x90)
$previousRestoreTwoHook = New-RelativeJumpBytes 0x4D9B4A ($patchVa + 0x180)
$previousRestoreTwoHook += [byte[]]@(0x90)
$oldOptionsSaveHook = New-RelativeJumpBytes 0x4881F0 $patchVa
$oldOptionsSaveHook += [byte[]]@(0x90, 0x90)
$oldOptionsRestoreHook = New-RelativeJumpBytes 0x473A8D ($patchVa + 0x200)
$oldSpeedSaveHook = New-RelativeJumpBytes 0x4D9B4A ($patchVa + 0x300)
$oldSpeedSaveHook += [byte[]]@(0x90)
$oldSpeedRestoreHook = New-RelativeJumpBytes 0x4D90F9 ($patchVa + 0x380)
$oldSpeedRestoreHook += [byte[]]@(0x90)

$sliderIsPatched = Test-BytesEqual $bytes $SpeedSliderSaveOffset $sliderHook
$restoreOneIsPatched = Test-BytesEqual $bytes $SpeedRestoreOneOffset $restoreOneHook
$restoreTwoIsPatched = Test-BytesEqual $bytes $SpeedRestoreTwoOffset $restoreTwoHook
$restoreTwoPreviousPatched = Test-BytesEqual $bytes $SpeedRestoreTwoOffset $previousRestoreTwoHook
$copyOneIsPatched = Test-BytesEqual $bytes $SpeedCopyOneOffset $copyOneHook
$copyTwoIsPatched = Test-BytesEqual $bytes $SpeedCopyTwoOffset $copyTwoHook
$objectInitOneIsPatched = Test-BytesEqual $bytes $SpeedObjectInitOneOffset $objectInitOneHook
$objectInitTwoIsPatched = Test-BytesEqual $bytes $SpeedObjectInitTwoOffset $objectInitTwoHook
$objectInitThreeIsPatched = Test-BytesEqual $bytes $SpeedObjectInitThreeOffset $objectInitThreeHook
$optionsSaveOldPatched = Test-BytesEqual $bytes $OldOptionsSaveOffset $oldOptionsSaveHook
$optionsRestoreOldPatched = Test-BytesEqual $bytes $OldOptionsRestoreOffset $oldOptionsRestoreHook
$restoreOneOldPatched = Test-BytesEqual $bytes $SpeedRestoreOneOffset $oldSpeedRestoreHook
$restoreTwoOldPatched = Test-BytesEqual $bytes $SpeedRestoreTwoOffset $oldSpeedSaveHook

if (-not ($sliderIsPatched -or $restoreOneIsPatched -or $restoreTwoIsPatched -or $restoreTwoPreviousPatched -or $copyOneIsPatched -or $copyTwoIsPatched -or $objectInitOneIsPatched -or $objectInitTwoIsPatched -or $objectInitThreeIsPatched -or $optionsSaveOldPatched -or $optionsRestoreOldPatched -or $restoreOneOldPatched -or $restoreTwoOldPatched)) {
    Write-Host "MajestyHD.exe: no Remember Game Speed hooks are installed."
    return
}

if ($section.Index -ne ($pe.SectionCount - 1)) {
    throw ".mskp is not the last PE section. Refusing to remove it automatically."
}

$previousSection = $pe.Sections | Where-Object { $_.Index -eq ($section.Index - 1) } | Select-Object -First 1
$restoredFileSize = [int]$section.RawOffset
$restoredSizeOfImage = Align-Value ([uint32]($previousSection.Rva + [Math]::Max($previousSection.VirtualSize, $previousSection.RawSize))) ([uint32]$pe.SectionAlignment)

if ($DryRun) {
    if ($sliderIsPatched) {
        Write-Host ("MajestyHD.exe: would restore slider-save hook at file offset 0x{0:X}." -f $SpeedSliderSaveOffset)
    }
    if ($restoreOneIsPatched -or $restoreOneOldPatched) {
        Write-Host ("MajestyHD.exe: would restore quest-speed hook at file offset 0x{0:X}." -f $SpeedRestoreOneOffset)
    }
    if ($restoreTwoIsPatched -or $restoreTwoPreviousPatched -or $restoreTwoOldPatched) {
        Write-Host ("MajestyHD.exe: would restore alternate quest-speed hook at file offset 0x{0:X}." -f $SpeedRestoreTwoOffset)
    }
    if ($copyOneIsPatched) {
        Write-Host ("MajestyHD.exe: would restore UI speed-copy hook at file offset 0x{0:X}." -f $SpeedCopyOneOffset)
    }
    if ($copyTwoIsPatched) {
        Write-Host ("MajestyHD.exe: would restore alternate UI speed-copy hook at file offset 0x{0:X}." -f $SpeedCopyTwoOffset)
    }
    if ($objectInitOneIsPatched) {
        Write-Host ("MajestyHD.exe: would restore game-speed object hook at file offset 0x{0:X}." -f $SpeedObjectInitOneOffset)
    }
    if ($objectInitTwoIsPatched) {
        Write-Host ("MajestyHD.exe: would restore new-quest game-speed object hook at file offset 0x{0:X}." -f $SpeedObjectInitTwoOffset)
    }
    if ($objectInitThreeIsPatched) {
        Write-Host ("MajestyHD.exe: would restore alternate new-quest game-speed object hook at file offset 0x{0:X}." -f $SpeedObjectInitThreeOffset)
    }
    if ($optionsSaveOldPatched -or $optionsRestoreOldPatched) {
        Write-Host "MajestyHD.exe: would restore old runtime-options/audio hooks."
    }
    Write-Host ("MajestyHD.exe: would remove .mskp section header at file offset 0x{0:X}." -f $section.HeaderOffset)
    Write-Host ("MajestyHD.exe: would truncate appended .mskp data back to file offset 0x{0:X}." -f $restoredFileSize)
    return
}

Assert-FileWritable $exePath

$restoredBytes = New-Object byte[] $restoredFileSize
[Array]::Copy($bytes, 0, $restoredBytes, 0, $restoredFileSize)

if ($sliderIsPatched) {
    Write-Bytes $restoredBytes $SpeedSliderSaveOffset $OriginalSliderSaveBytes
}
if ($restoreOneIsPatched -or $restoreOneOldPatched) {
    Write-Bytes $restoredBytes $SpeedRestoreOneOffset $OriginalSpeedWriteBytes
}
if ($restoreTwoIsPatched -or $restoreTwoPreviousPatched -or $restoreTwoOldPatched) {
    Write-Bytes $restoredBytes $SpeedRestoreTwoOffset $OriginalSpeedWriteBytes
}
if ($copyOneIsPatched) {
    Write-Bytes $restoredBytes $SpeedCopyOneOffset $OriginalSpeedWriteEdxBytes
}
if ($copyTwoIsPatched) {
    Write-Bytes $restoredBytes $SpeedCopyTwoOffset $OriginalSpeedWriteBytes
}
if ($objectInitOneIsPatched) {
    Write-Bytes $restoredBytes $SpeedObjectInitOneOffset $OriginalSpeedWriteEbxObjectBytes
}
if ($objectInitTwoIsPatched) {
    Write-Bytes $restoredBytes $SpeedObjectInitTwoOffset $OriginalSpeedWriteEsiObjectBytes
}
if ($objectInitThreeIsPatched) {
    Write-Bytes $restoredBytes $SpeedObjectInitThreeOffset $OriginalSpeedWriteEsiObjectBytes
}
if ($optionsSaveOldPatched) {
    Write-Bytes $restoredBytes $OldOptionsSaveOffset $OriginalOptionsSaveBytes
}
if ($optionsRestoreOldPatched) {
    Write-Bytes $restoredBytes $OldOptionsRestoreOffset $OriginalOptionsRestoreBytes
}

[BitConverter]::GetBytes([uint16]($pe.SectionCount - 1)).CopyTo($restoredBytes, $pe.SectionCountOffset)
[BitConverter]::GetBytes([uint32]$restoredSizeOfImage).CopyTo($restoredBytes, $pe.SizeOfImageOffset)
Write-Bytes $restoredBytes $section.HeaderOffset (New-Object byte[] 40)

[IO.File]::WriteAllBytes($exePath, $restoredBytes)

Write-Host "Done. Majesty's stock game-speed behavior is restored."
