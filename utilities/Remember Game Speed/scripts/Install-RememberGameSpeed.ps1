param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "NativePathEncoding.ps1")

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_remember_game_speed_originals"

# PE section characteristics: code, execute, read, write. The section holds runtime scratch state.
$SectionCharacteristics = 3758096416  # 0xE0000020: code, execute, read, write

$PatchSectionName = ".mskp"
$PatchRawSize = 0x1000
$PatchVirtualSize = 0x800

$SpeedSliderSaveVa = 0x46AF18
$SpeedSliderSaveOffset = 0x6A318
$SpeedStepSlowerVa = 0x4644F3
$SpeedStepSlowerOffset = 0x638F3
$SpeedStepFasterVa = 0x464595
$SpeedStepFasterOffset = 0x63995
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

function New-PatchBlob {
    param(
        [uint32]$PatchVa,
        [Parameter(Mandatory = $true)][byte[]]$PreferencePathBytes
    )

    $bytes = New-Object byte[] $PatchRawSize
    $speedFileNameVa = $PatchVa + 0x600
    $wbVa = $PatchVa + 0x700
    $rbVa = $PatchVa + 0x703
    $speedTempVa = $PatchVa + 0x780
    $dirtyFlagVa = $PatchVa + 0x784
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

    [byte[]]$saveSteppedSpeed = @(
        0x89, 0xB0, 0x98, 0x00, 0x00, 0x00,
        0x89, 0x35, 0, 0, 0, 0,
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
        0xC3
    )
    Set-Bytes 0x550 $saveSteppedSpeed
    Set-UInt32 0x558 $speedTempVa
    Set-UInt32 0x55E $dirtyFlagVa
    Set-UInt32 0x565 $wbVa
    Set-UInt32 0x56A $speedFileNameVa
    Set-UInt32 0x570 $FopenIat
    Set-UInt32 0x583 $speedTempVa
    Set-UInt32 0x589 $FwriteIat
    Set-UInt32 0x593 $FcloseIat

    Set-Bytes 0x600 $PreferencePathBytes
    $bytes[0x600 + $PreferencePathBytes.Length] = 0
    Set-AsciiZ 0x700 "wb"
    Set-AsciiZ 0x703 "rb"

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
$backupPath = Join-Path $backupDir "MajestyHD.exe.before-remember-game-speed"
$preferenceDir = Join-Path (
    [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
) "MajestyHD"
$preferencePath = Join-Path $preferenceDir "MajestySessionSpeed.bin"
$legacyPreferencePath = Join-Path $resolvedGamePath "MajestySessionSpeed.bin"
[byte[]]$preferencePathBytes = ConvertTo-MajestyNarrowPathBytes `
    -Path $preferencePath `
    -UtilityName "Remember Game Speed"
if ($preferencePathBytes.Length -ge 0x100) {
    throw "The Remember Game Speed preference path is too long to embed safely: $preferencePath. No game files were changed."
}

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

$patchBlob = New-PatchBlob $patchSectionVa $preferencePathBytes
$newSliderHook = New-RelativeJumpBytes $SpeedSliderSaveVa $patchSectionVa
$newStepSlowerHook = New-RelativeCallBytes $SpeedStepSlowerVa ($patchSectionVa + 0x550)
$newStepSlowerHook += [byte[]]@(0x90)
$newStepFasterHook = New-RelativeCallBytes $SpeedStepFasterVa ($patchSectionVa + 0x550)
$newStepFasterHook += [byte[]]@(0x90)
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
$stepSlowerIsStock = Test-BytesEqual $bytes $SpeedStepSlowerOffset $OriginalSpeedWriteEsiObjectBytes
$stepSlowerAlreadyPatched = Test-BytesEqual $bytes $SpeedStepSlowerOffset $newStepSlowerHook
$stepFasterIsStock = Test-BytesEqual $bytes $SpeedStepFasterOffset $OriginalSpeedWriteEsiObjectBytes
$stepFasterAlreadyPatched = Test-BytesEqual $bytes $SpeedStepFasterOffset $newStepFasterHook
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

# The Speedrun Timer hooks these same two sites directly when it is installed
# without us. Recognise its hooks as a valid prior state and take the sites
# over: our blocks replay the displaced instruction and then hand control to
# the timer through the bridge below, which is exactly the layout produced by
# installing in the opposite order. The timer's now-unused direct stubs stay
# in its own section and are harmless.
$speedrunSection = $pe.Sections | Where-Object { $_.Name -eq ".msrt" } | Select-Object -First 1
$speedrunDirectHookTwo = $null
$speedrunDirectHookThree = $null
$objectInitTwoIsSpeedrunDirect = $false
$objectInitThreeIsSpeedrunDirect = $false
if ($speedrunSection) {
    $speedrunSectionVa = [uint32]($pe.ImageBase + $speedrunSection.Rva)
    $speedrunDirectHookTwo = (New-RelativeJumpBytes $SpeedObjectInitTwoVa ([uint32]($speedrunSectionVa + 0x140))) + [byte[]]@(0x90)
    $speedrunDirectHookThree = (New-RelativeJumpBytes $SpeedObjectInitThreeVa ([uint32]($speedrunSectionVa + 0x160))) + [byte[]]@(0x90)
    $objectInitTwoIsSpeedrunDirect = Test-BytesEqual $bytes $SpeedObjectInitTwoOffset $speedrunDirectHookTwo
    $objectInitThreeIsSpeedrunDirect = Test-BytesEqual $bytes $SpeedObjectInitThreeOffset $speedrunDirectHookThree
}
$optionsSaveOldPatched = Test-BytesEqual $bytes $OldOptionsSaveOffset $oldOptionsSaveHook
$optionsSaveIsStock = Test-BytesEqual $bytes $OldOptionsSaveOffset $OriginalOptionsSaveBytes
$optionsRestoreOldPatched = Test-BytesEqual $bytes $OldOptionsRestoreOffset $oldOptionsRestoreHook
$optionsRestoreIsStock = Test-BytesEqual $bytes $OldOptionsRestoreOffset $OriginalOptionsRestoreBytes
$headerAlreadyPatched = $existingSection -and (Test-BytesEqual $bytes $patchSectionHeaderOffset $patchSectionHeader)
$blobAlreadyPatched = $existingSection -and (Test-BytesEqual $bytes $patchSectionRawOffset $patchBlob)
$speedrunBlob = $null
$blobHasSpeedrunBridges = $false
# Build the Speedrun Timer bridge whenever the timer is present. This used to
# also require $existingSection, which meant a first-time install onto a game
# that already had the timer left $speedrunBlob null. $blobToWrite below then
# selected that null, and the byte writer silently wrote nothing, producing a
# zeroed .mskp section with ten live hooks pointing into it.
if ($speedrunSection) {
    $speedrunVa = [uint32]($pe.ImageBase + $speedrunSection.Rva)
    $speedrunBlob = New-Object byte[] $PatchRawSize
    [Array]::Copy($patchBlob, $speedrunBlob, $PatchRawSize)
    Write-Bytes $speedrunBlob 0x429 (New-RelativeJumpBytes ([uint32]($patchSectionVa + 0x429)) ([uint32]($speedrunVa + 0x100)))
    Write-Bytes $speedrunBlob 0x469 (New-RelativeJumpBytes ([uint32]($patchSectionVa + 0x469)) ([uint32]($speedrunVa + 0x130)))
    $blobHasSpeedrunBridges = Test-BytesEqual $bytes $patchSectionRawOffset $speedrunBlob
}
$installedBlobMatchesLayout = if ($speedrunSection) {
    $blobHasSpeedrunBridges
} else {
    $blobAlreadyPatched
}

if (-not ($sliderIsStock -or $sliderAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the slider-save hook 0x{0:X}." -f $SpeedSliderSaveOffset)
}
if (-not ($stepSlowerIsStock -or $stepSlowerAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the slower-speed save hook 0x{0:X}." -f $SpeedStepSlowerOffset)
}
if (-not ($stepFasterIsStock -or $stepFasterAlreadyPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the faster-speed save hook 0x{0:X}." -f $SpeedStepFasterOffset)
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
if (-not ($objectInitTwoIsStock -or $objectInitTwoAlreadyPatched -or $objectInitTwoIsSpeedrunDirect)) {
    throw ("MajestyHD.exe has unexpected bytes at game-speed object hook 0x{0:X}." -f $SpeedObjectInitTwoOffset)
}
if (-not ($objectInitThreeIsStock -or $objectInitThreeAlreadyPatched -or $objectInitThreeIsSpeedrunDirect)) {
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
Write-Host "Preset file: $preferencePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($existingSection -and $headerAlreadyPatched -and $sliderAlreadyPatched -and $stepSlowerAlreadyPatched -and $stepFasterAlreadyPatched -and $restoreOneAlreadyPatched -and $restoreTwoAlreadyPatched -and $copyOneAlreadyPatched -and $copyTwoAlreadyPatched -and $objectInitOneAlreadyPatched -and $objectInitTwoAlreadyPatched -and $objectInitThreeAlreadyPatched -and $optionsSaveIsStock -and $optionsRestoreIsStock -and $installedBlobMatchesLayout) {
    Write-Host "MajestyHD.exe: Remember Game Speed is already installed."
    if ($blobHasSpeedrunBridges) {
        Write-Host "MajestyHD.exe: Speedrun Timer integration is present and preserved."
    }
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
    if (-not $stepSlowerAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch slower-speed save hook at file offset 0x{0:X}." -f $SpeedStepSlowerOffset)
    }
    if (-not $stepFasterAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch faster-speed save hook at file offset 0x{0:X}." -f $SpeedStepFasterOffset)
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

if (-not (Test-Path -LiteralPath $preferenceDir)) {
    New-Item -ItemType Directory -Path $preferenceDir | Out-Null
}
if (
    (-not (Test-Path -LiteralPath $preferencePath)) -and
    (Test-Path -LiteralPath $legacyPreferencePath)
) {
    Copy-Item -LiteralPath $legacyPreferencePath -Destination $preferencePath
}

Save-PreInstallBackup $exePath $backupDir $backupPath "Remember Game Speed"

$targetFileSize = if ($existingSection) { $bytes.Length } else { $patchedFileSize }
$patchedBytes = New-Object byte[] $targetFileSize
[Array]::Copy($bytes, 0, $patchedBytes, 0, $bytes.Length)

if (-not $existingSection) {
    [BitConverter]::GetBytes([uint16]($pe.SectionCount + 1)).CopyTo($patchedBytes, $pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$newSizeOfImage).CopyTo($patchedBytes, $pe.SizeOfImageOffset)
}
Write-Bytes $patchedBytes $patchSectionHeaderOffset $patchSectionHeader

$blobToWrite = if ($speedrunSection) { $speedrunBlob } else { $patchBlob }
Write-Bytes $patchedBytes $patchSectionRawOffset $blobToWrite
Write-Bytes $patchedBytes $SpeedSliderSaveOffset $newSliderHook
Write-Bytes $patchedBytes $SpeedStepSlowerOffset $newStepSlowerHook
Write-Bytes $patchedBytes $SpeedStepFasterOffset $newStepFasterHook
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
