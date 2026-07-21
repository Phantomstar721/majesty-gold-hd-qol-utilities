param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_remember_game_speed_originals"

$PatchSectionName = ".mskp"
$PatchRawSize = 0x1000
$PatchVirtualSize = 0x800

$SpeedSliderSaveVa = 0x46AF18
$SpeedSliderSaveOffset = 0x6A318
$SpeedRestoreOneVa = 0x4D90F9
$SpeedRestoreOneOffset = 0xD84F9
$SpeedRestoreTwoVa = 0x4D9B4A
$SpeedRestoreTwoOffset = 0xD8F4A
$SpeedCopyOneVa = 0x46A0C4
$SpeedCopyOneOffset = 0x694C4
$SpeedCopyTwoVa = 0x46A209
$SpeedCopyTwoOffset = 0x69609
$SpeedObjectInitOneVa = 0x484DD2
$SpeedObjectInitOneOffset = 0x841D2
$SpeedObjectInitTwoVa = 0x429006
$SpeedObjectInitTwoOffset = 0x28406
$SpeedObjectInitThreeVa = 0x429019
$SpeedObjectInitThreeOffset = 0x28419

$OldOptionsSaveVa = 0x4881F0
$OldOptionsSaveOffset = 0x875F0
$OldOptionsRestoreVa = 0x473A8D
$OldOptionsRestoreOffset = 0x72E8D

$OriginalSliderSaveBytes = [byte[]]@(0xA3, 0x04, 0x53, 0x7B, 0x00)
$OriginalSpeedWriteBytes = [byte[]]@(0x89, 0x0D, 0x04, 0x53, 0x7B, 0x00)
$OriginalSpeedWriteEdxBytes = [byte[]]@(0x89, 0x15, 0x04, 0x53, 0x7B, 0x00)
$OriginalSpeedWriteEbxObjectBytes = [byte[]]@(0x89, 0x98, 0x98, 0x00, 0x00, 0x00)
$OriginalSpeedWriteEsiObjectBytes = [byte[]]@(0x89, 0xB0, 0x98, 0x00, 0x00, 0x00)
$OriginalOptionsSaveBytes = [byte[]]@(0x6A, 0xFF, 0x68, 0xAB, 0xEF, 0x6E, 0x00)
$OriginalOptionsRestoreBytes = [byte[]]@(0xE8, 0xAE, 0x19, 0x08, 0x00)

$FopenIat = 0x735430
$FreadIat = 0x735434
$FwriteIat = 0x735438
$FcloseIat = 0x735444
$GetGameVa = 0x4D6FC0

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
    $imageBase = Read-U32 $Bytes ($optionalHeaderOffset + 28)
    $sectionAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 32)
    $fileAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 36)
    $sizeOfImageOffset = $optionalHeaderOffset + 56
    $sizeOfHeaders = Read-U32 $Bytes ($optionalHeaderOffset + 60)
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
        ImageBase = $imageBase
        SectionAlignment = $sectionAlignment
        FileAlignment = $fileAlignment
        SizeOfImageOffset = $sizeOfImageOffset
        SizeOfImage = Read-U32 $Bytes $sizeOfImageOffset
        SizeOfHeaders = $sizeOfHeaders
        SectionTableOffset = $sectionTableOffset
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

function New-RelativeCallBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE8
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
    [BitConverter]::GetBytes([uint32]3758096416).CopyTo($bytes, 36)
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

    for ($i = 0; $i -lt $Patch.Length; $i++) {
        $Bytes[$Offset + $i] = $Patch[$i]
    }
}

function New-PatchBlob {
    param([uint32]$PatchVa)

    $bytes = New-Object byte[] $PatchRawSize
    $speedFileNameVa = $PatchVa + 0x600
    $wbVa = $PatchVa + 0x640
    $rbVa = $PatchVa + 0x643
    $speedTempVa = $PatchVa + 0x700
    $dirtyFlagVa = $PatchVa + 0x704
    $loadSpeedVa = $PatchVa + 0x500

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

    [byte[]]$saveSlider = @(
        0xA3, 0x04, 0x53, 0x7B, 0x00,
        0xA3, 0, 0, 0, 0,
        0xC6, 0x05, 0, 0, 0, 0, 0x01,
        0x60,
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
    Set-Bytes 0x000 $saveSlider
    Set-UInt32 0x006 $speedTempVa
    Set-UInt32 0x00C $dirtyFlagVa
    Set-UInt32 0x013 $wbVa
    Set-UInt32 0x018 $speedFileNameVa
    Set-UInt32 0x01E $FopenIat
    Set-UInt32 0x031 $speedTempVa
    Set-UInt32 0x037 $FwriteIat
    Set-UInt32 0x041 $FcloseIat
    (New-RelativeJumpBytes ($PatchVa + 0x049) ($SpeedSliderSaveVa + 0x05)).CopyTo($bytes, 0x049)

    function Set-RestoreBlock {
        param(
            [int]$Offset,
            [uint32]$SourceVa,
            [uint32]$BackVa
        )

        [byte[]]$restore = @(
            0x89, 0x0D, 0x04, 0x53, 0x7B, 0x00,
            0x60,
            0x80, 0x3D, 0, 0, 0, 0, 0x00,
            0x74, 0x1D,
            0xE8, 0, 0, 0, 0,
            0x8B, 0x15, 0, 0, 0, 0,
            0x89, 0x15, 0x04, 0x53, 0x7B, 0x00,
            0x89, 0x90, 0x98, 0x00, 0x00, 0x00,
            0x61,
            0xE9, 0, 0, 0, 0,
            0x68, 0, 0, 0, 0,
            0x68, 0, 0, 0, 0,
            0xFF, 0x15, 0, 0, 0, 0,
            0x83, 0xC4, 0x08,
            0x85, 0xC0,
            0x74, 0x3C,
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
            0x74, 0x17,
            0xE8, 0, 0, 0, 0,
            0x8B, 0x15, 0, 0, 0, 0,
            0x89, 0x15, 0x04, 0x53, 0x7B, 0x00,
            0x89, 0x90, 0x98, 0x00, 0x00, 0x00,
            0x61,
            0xE9, 0, 0, 0, 0
        )
        Set-Bytes $Offset $restore
        Set-UInt32 ($Offset + 0x009) $dirtyFlagVa
        (New-RelativeCallBytes ($PatchVa + $Offset + 0x010) $GetGameVa).CopyTo($bytes, $Offset + 0x010)
        Set-UInt32 ($Offset + 0x017) $speedTempVa
        (New-RelativeJumpBytes ($PatchVa + $Offset + 0x028) $BackVa).CopyTo($bytes, $Offset + 0x028)
        Set-UInt32 ($Offset + 0x02E) $rbVa
        Set-UInt32 ($Offset + 0x033) $speedFileNameVa
        Set-UInt32 ($Offset + 0x039) $FopenIat
        Set-UInt32 ($Offset + 0x04C) $speedTempVa
        Set-UInt32 ($Offset + 0x052) $FreadIat
        Set-UInt32 ($Offset + 0x05E) $FcloseIat
        (New-RelativeCallBytes ($PatchVa + $Offset + 0x069) $GetGameVa).CopyTo($bytes, $Offset + 0x069)
        Set-UInt32 ($Offset + 0x070) $speedTempVa
        (New-RelativeJumpBytes ($PatchVa + $Offset + 0x081) $BackVa).CopyTo($bytes, $Offset + 0x081)
    }

    Set-RestoreBlock 0x100 $SpeedRestoreOneVa ($SpeedRestoreOneVa + 0x06)
    Set-RestoreBlock 0x240 $SpeedRestoreTwoVa ($SpeedRestoreTwoVa + 0x06)

    [byte[]]$copyEdx = @(
        0x80, 0x3D, 0, 0, 0, 0, 0x00,
        0x74, 0x0C,
        0x8B, 0x15, 0, 0, 0, 0,
        0x89, 0x90, 0x98, 0x00, 0x00, 0x00,
        0x89, 0x15, 0x04, 0x53, 0x7B, 0x00,
        0xE9, 0, 0, 0, 0
    )
    Set-Bytes 0x340 $copyEdx
    Set-UInt32 0x342 $dirtyFlagVa
    Set-UInt32 0x34B $speedTempVa
    (New-RelativeJumpBytes ($PatchVa + 0x35B) ($SpeedCopyOneVa + 0x06)).CopyTo($bytes, 0x35B)

    [byte[]]$copyEcx = @(
        0x80, 0x3D, 0, 0, 0, 0, 0x00,
        0x74, 0x0C,
        0x8B, 0x0D, 0, 0, 0, 0,
        0x89, 0x88, 0x98, 0x00, 0x00, 0x00,
        0x89, 0x0D, 0x04, 0x53, 0x7B, 0x00,
        0xE9, 0, 0, 0, 0
    )
    Set-Bytes 0x380 $copyEcx
    Set-UInt32 0x382 $dirtyFlagVa
    Set-UInt32 0x38B $speedTempVa
    (New-RelativeJumpBytes ($PatchVa + 0x39B) ($SpeedCopyTwoVa + 0x06)).CopyTo($bytes, 0x39B)

    function Set-ObjectSpeedBlock {
        param(
            [int]$Offset,
            [uint32]$SourceVa,
            [uint32]$BackVa,
            [byte]$LoadModRm,
            [byte[]]$ObjectWriteBytes,
            [byte[]]$GlobalWriteBytes
        )

        [byte[]]$restore = @(
            0x80, 0x3D, 0, 0, 0, 0, 0x00,
            0x75, 0x0E,
            0xE8, 0, 0, 0, 0,
            0x80, 0x3D, 0, 0, 0, 0, 0x00,
            0x74, 0x06,
            0x8B, $LoadModRm, 0x00, 0x00, 0x00, 0x00
        )
        $restore += $ObjectWriteBytes
        $restore += $GlobalWriteBytes
        $restore += [byte[]]@(0xE9, 0, 0, 0, 0)

        Set-Bytes $Offset $restore
        Set-UInt32 ($Offset + 0x002) $dirtyFlagVa
        (New-RelativeCallBytes ($PatchVa + $Offset + 0x009) $loadSpeedVa).CopyTo($bytes, $Offset + 0x009)
        Set-UInt32 ($Offset + 0x010) $dirtyFlagVa
        Set-UInt32 ($Offset + 0x019) $speedTempVa
        (New-RelativeJumpBytes ($PatchVa + $Offset + $restore.Length - 5) $BackVa).CopyTo($bytes, $Offset + $restore.Length - 5)
    }

    Set-ObjectSpeedBlock 0x3C0 $SpeedObjectInitOneVa ($SpeedObjectInitOneVa + 0x06) 0x1D $OriginalSpeedWriteEbxObjectBytes ([byte[]]@(0x89, 0x1D, 0x04, 0x53, 0x7B, 0x00))
    Set-ObjectSpeedBlock 0x400 $SpeedObjectInitTwoVa ($SpeedObjectInitTwoVa + 0x06) 0x35 $OriginalSpeedWriteEsiObjectBytes ([byte[]]@(0x89, 0x35, 0x04, 0x53, 0x7B, 0x00))
    Set-ObjectSpeedBlock 0x440 $SpeedObjectInitThreeVa ($SpeedObjectInitThreeVa + 0x06) 0x35 $OriginalSpeedWriteEsiObjectBytes ([byte[]]@(0x89, 0x35, 0x04, 0x53, 0x7B, 0x00))

    [byte[]]$loadSpeed = @(
        0x60,
        0x68, 0, 0, 0, 0,
        0x68, 0, 0, 0, 0,
        0xFF, 0x15, 0, 0, 0, 0,
        0x83, 0xC4, 0x08,
        0x85, 0xC0,
        0x74, 0x2C,
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
        0x74, 0x07,
        0xC6, 0x05, 0, 0, 0, 0, 0x01,
        0x61,
        0xC3
    )
    Set-Bytes 0x500 $loadSpeed
    Set-UInt32 0x502 $rbVa
    Set-UInt32 0x507 $speedFileNameVa
    Set-UInt32 0x50D $FopenIat
    Set-UInt32 0x520 $speedTempVa
    Set-UInt32 0x526 $FreadIat
    Set-UInt32 0x532 $FcloseIat
    Set-UInt32 0x53F $dirtyFlagVa

    Set-AsciiZ 0x600 "MajestySessionSpeed.bin"
    Set-AsciiZ 0x640 "wb"
    Set-AsciiZ 0x643 "rb"

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

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$backupDir = Join-Path $resolvedGamePath $BackupDirName
$backupPath = Join-Path $backupDir "MajestyHD.exe.before-remember-game-speed"

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

$patchBlob = New-PatchBlob $patchSectionVa
$newSliderHook = New-RelativeJumpBytes $SpeedSliderSaveVa $patchSectionVa
$newRestoreOneHook = New-RelativeJumpBytes $SpeedRestoreOneVa ($patchSectionVa + 0x100)
$newRestoreOneHook += [byte[]]@(0x90)
$newRestoreTwoHook = New-RelativeJumpBytes $SpeedRestoreTwoVa ($patchSectionVa + 0x240)
$newRestoreTwoHook += [byte[]]@(0x90)
$newCopyOneHook = New-RelativeJumpBytes $SpeedCopyOneVa ($patchSectionVa + 0x340)
$newCopyOneHook += [byte[]]@(0x90)
$newCopyTwoHook = New-RelativeJumpBytes $SpeedCopyTwoVa ($patchSectionVa + 0x380)
$newCopyTwoHook += [byte[]]@(0x90)
$newObjectInitOneHook = New-RelativeJumpBytes $SpeedObjectInitOneVa ($patchSectionVa + 0x3C0)
$newObjectInitOneHook += [byte[]]@(0x90)
$newObjectInitTwoHook = New-RelativeJumpBytes $SpeedObjectInitTwoVa ($patchSectionVa + 0x400)
$newObjectInitTwoHook += [byte[]]@(0x90)
$newObjectInitThreeHook = New-RelativeJumpBytes $SpeedObjectInitThreeVa ($patchSectionVa + 0x440)
$newObjectInitThreeHook += [byte[]]@(0x90)
$previousRestoreTwoHook = New-RelativeJumpBytes $SpeedRestoreTwoVa ($patchSectionVa + 0x180)
$previousRestoreTwoHook += [byte[]]@(0x90)
$oldOptionsSaveHook = New-RelativeJumpBytes $OldOptionsSaveVa $patchSectionVa
$oldOptionsSaveHook += [byte[]]@(0x90, 0x90)
$oldOptionsRestoreHook = New-RelativeJumpBytes $OldOptionsRestoreVa ($patchSectionVa + 0x200)
$oldSpeedSaveHook = New-RelativeJumpBytes $SpeedRestoreTwoVa ($patchSectionVa + 0x300)
$oldSpeedSaveHook += [byte[]]@(0x90)
$oldSpeedRestoreHook = New-RelativeJumpBytes $SpeedRestoreOneVa ($patchSectionVa + 0x380)
$oldSpeedRestoreHook += [byte[]]@(0x90)

$sliderIsStock = Test-BytesEqual $bytes $SpeedSliderSaveOffset $OriginalSliderSaveBytes
$sliderAlreadyPatched = Test-BytesEqual $bytes $SpeedSliderSaveOffset $newSliderHook
$restoreOneIsStock = Test-BytesEqual $bytes $SpeedRestoreOneOffset $OriginalSpeedWriteBytes
$restoreOneAlreadyPatched = Test-BytesEqual $bytes $SpeedRestoreOneOffset $newRestoreOneHook
$restoreOneOldPatched = Test-BytesEqual $bytes $SpeedRestoreOneOffset $oldSpeedRestoreHook
$restoreTwoIsStock = Test-BytesEqual $bytes $SpeedRestoreTwoOffset $OriginalSpeedWriteBytes
$restoreTwoAlreadyPatched = Test-BytesEqual $bytes $SpeedRestoreTwoOffset $newRestoreTwoHook
$restoreTwoPreviousPatched = Test-BytesEqual $bytes $SpeedRestoreTwoOffset $previousRestoreTwoHook
$restoreTwoOldPatched = Test-BytesEqual $bytes $SpeedRestoreTwoOffset $oldSpeedSaveHook
$copyOneIsStock = Test-BytesEqual $bytes $SpeedCopyOneOffset $OriginalSpeedWriteEdxBytes
$copyOneAlreadyPatched = Test-BytesEqual $bytes $SpeedCopyOneOffset $newCopyOneHook
$copyTwoIsStock = Test-BytesEqual $bytes $SpeedCopyTwoOffset $OriginalSpeedWriteBytes
$copyTwoAlreadyPatched = Test-BytesEqual $bytes $SpeedCopyTwoOffset $newCopyTwoHook
$objectInitOneIsStock = Test-BytesEqual $bytes $SpeedObjectInitOneOffset $OriginalSpeedWriteEbxObjectBytes
$objectInitOneAlreadyPatched = Test-BytesEqual $bytes $SpeedObjectInitOneOffset $newObjectInitOneHook
$objectInitTwoIsStock = Test-BytesEqual $bytes $SpeedObjectInitTwoOffset $OriginalSpeedWriteEsiObjectBytes
$objectInitTwoAlreadyPatched = Test-BytesEqual $bytes $SpeedObjectInitTwoOffset $newObjectInitTwoHook
$objectInitThreeIsStock = Test-BytesEqual $bytes $SpeedObjectInitThreeOffset $OriginalSpeedWriteEsiObjectBytes
$objectInitThreeAlreadyPatched = Test-BytesEqual $bytes $SpeedObjectInitThreeOffset $newObjectInitThreeHook
$optionsSaveOldPatched = Test-BytesEqual $bytes $OldOptionsSaveOffset $oldOptionsSaveHook
$optionsSaveIsStock = Test-BytesEqual $bytes $OldOptionsSaveOffset $OriginalOptionsSaveBytes
$optionsRestoreOldPatched = Test-BytesEqual $bytes $OldOptionsRestoreOffset $oldOptionsRestoreHook
$optionsRestoreIsStock = Test-BytesEqual $bytes $OldOptionsRestoreOffset $OriginalOptionsRestoreBytes
$headerAlreadyPatched = $existingSection -and (Test-BytesEqual $bytes $patchSectionHeaderOffset $patchSectionHeader)
$blobAlreadyPatched = $existingSection -and (Test-BytesEqual $bytes $patchSectionRawOffset $patchBlob)

if (-not ($sliderIsStock -or $sliderAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the slider-save hook 0x{0:X}." -f $SpeedSliderSaveOffset)
}
if (-not ($restoreOneIsStock -or $restoreOneAlreadyPatched -or $restoreOneOldPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at speed-restore hook 0x{0:X}." -f $SpeedRestoreOneOffset)
}
if (-not ($restoreTwoIsStock -or $restoreTwoAlreadyPatched -or $restoreTwoPreviousPatched -or $restoreTwoOldPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at speed-restore hook 0x{0:X}." -f $SpeedRestoreTwoOffset)
}
if (-not ($copyOneIsStock -or $copyOneAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at speed-copy hook 0x{0:X}." -f $SpeedCopyOneOffset)
}
if (-not ($copyTwoIsStock -or $copyTwoAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at speed-copy hook 0x{0:X}." -f $SpeedCopyTwoOffset)
}
if (-not ($objectInitOneIsStock -or $objectInitOneAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at game-speed object hook 0x{0:X}." -f $SpeedObjectInitOneOffset)
}
if (-not ($objectInitTwoIsStock -or $objectInitTwoAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at game-speed object hook 0x{0:X}." -f $SpeedObjectInitTwoOffset)
}
if (-not ($objectInitThreeIsStock -or $objectInitThreeAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at game-speed object hook 0x{0:X}." -f $SpeedObjectInitThreeOffset)
}
if (-not ($optionsSaveIsStock -or $optionsSaveOldPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the old options-save hook 0x{0:X}." -f $OldOptionsSaveOffset)
}
if (-not ($optionsRestoreIsStock -or $optionsRestoreOldPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the old options-restore hook 0x{0:X}." -f $OldOptionsRestoreOffset)
}
if ($existingSection -and $bytes.Length -lt $patchedFileSize) {
    throw ("MajestyHD.exe has a .mskp header but is too short: 0x{0:X}, expected at least 0x{1:X}." -f $bytes.Length, $patchedFileSize)
}

$newSizeOfImage = Align-Value ([uint32]($patchSectionRva + $PatchVirtualSize)) ([uint32]$pe.SectionAlignment)

Write-Host "Majesty Gold HD Remember Game Speed installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Preset file: MajestySessionSpeed.bin"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($existingSection -and $headerAlreadyPatched -and $sliderAlreadyPatched -and $restoreOneAlreadyPatched -and $restoreTwoAlreadyPatched -and $copyOneAlreadyPatched -and $copyTwoAlreadyPatched -and $objectInitOneAlreadyPatched -and $objectInitTwoAlreadyPatched -and $objectInitThreeAlreadyPatched -and $optionsSaveIsStock -and $optionsRestoreIsStock -and $blobAlreadyPatched) {
    Write-Host "MajestyHD.exe: Remember Game Speed is already installed."
    return
}

if ($DryRun) {
    if (-not $existingSection) {
        Write-Host ("MajestyHD.exe: would add .mskp section header at file offset 0x{0:X}." -f $patchSectionHeaderOffset)
        Write-Host ("MajestyHD.exe: would append .mskp section data at file offset 0x{0:X}." -f $patchSectionRawOffset)
    } else {
        Write-Host ("MajestyHD.exe: would update .mskp section data at file offset 0x{0:X}." -f $patchSectionRawOffset)
    }
    if (-not $sliderAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch slider-save hook at file offset 0x{0:X}." -f $SpeedSliderSaveOffset)
    }
    if (-not $restoreOneAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch quest-speed restore hook at file offset 0x{0:X}." -f $SpeedRestoreOneOffset)
    }
    if (-not $restoreTwoAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch alternate quest-speed restore hook at file offset 0x{0:X}." -f $SpeedRestoreTwoOffset)
    }
    if (-not $copyOneAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch UI speed-copy hook at file offset 0x{0:X}." -f $SpeedCopyOneOffset)
    }
    if (-not $copyTwoAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch alternate UI speed-copy hook at file offset 0x{0:X}." -f $SpeedCopyTwoOffset)
    }
    if (-not $objectInitOneAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch game-speed object hook at file offset 0x{0:X}." -f $SpeedObjectInitOneOffset)
    }
    if (-not $objectInitTwoAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch new-quest game-speed object hook at file offset 0x{0:X}." -f $SpeedObjectInitTwoOffset)
    }
    if (-not $objectInitThreeAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch alternate new-quest game-speed object hook at file offset 0x{0:X}." -f $SpeedObjectInitThreeOffset)
    }
    if ($optionsSaveOldPatched -or $optionsRestoreOldPatched) {
        Write-Host "MajestyHD.exe: would remove old runtime-options/audio blob hooks."
    }
    return
}

Assert-FileWritable $exePath

if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir | Out-Null
}
if (-not (Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $exePath -Destination $backupPath
}

$patchedBytes = New-Object byte[] $patchedFileSize
[Array]::Copy($bytes, 0, $patchedBytes, 0, $bytes.Length)

if (-not $existingSection) {
    [BitConverter]::GetBytes([uint16]($pe.SectionCount + 1)).CopyTo($patchedBytes, $pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$newSizeOfImage).CopyTo($patchedBytes, $pe.SizeOfImageOffset)
}
Write-Bytes $patchedBytes $patchSectionHeaderOffset $patchSectionHeader

Write-Bytes $patchedBytes $patchSectionRawOffset $patchBlob
Write-Bytes $patchedBytes $SpeedSliderSaveOffset $newSliderHook
Write-Bytes $patchedBytes $SpeedRestoreOneOffset $newRestoreOneHook
Write-Bytes $patchedBytes $SpeedRestoreTwoOffset $newRestoreTwoHook
Write-Bytes $patchedBytes $SpeedCopyOneOffset $newCopyOneHook
Write-Bytes $patchedBytes $SpeedCopyTwoOffset $newCopyTwoHook
Write-Bytes $patchedBytes $SpeedObjectInitOneOffset $newObjectInitOneHook
Write-Bytes $patchedBytes $SpeedObjectInitTwoOffset $newObjectInitTwoHook
Write-Bytes $patchedBytes $SpeedObjectInitThreeOffset $newObjectInitThreeHook
if ($optionsSaveOldPatched) {
    Write-Bytes $patchedBytes $OldOptionsSaveOffset $OriginalOptionsSaveBytes
}
if ($optionsRestoreOldPatched) {
    Write-Bytes $patchedBytes $OldOptionsRestoreOffset $OriginalOptionsRestoreBytes
}

[IO.File]::WriteAllBytes($exePath, $patchedBytes)

Write-Host "Done. Majesty should now remember the in-quest game-speed slider."
