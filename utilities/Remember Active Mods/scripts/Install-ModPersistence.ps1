param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_mod_persistence_originals"

$NumberOfSectionsOffset = 0x10E
$SizeOfImageOffset = 0x158
$NewSectionHeaderOffset = 0x2A0
$LoadCallOffset = 0x77D30
$LoadCallVa = 0x478930
$SaveCallOffset = 0x124196
$SaveCallVa = 0x524D96

$PatchSectionRawOffset = 0x3C0600
$PatchSectionRva = 0x40E000
$PatchSectionVa = 0x80E000
$PatchVirtualSize = 0x11AF
$PatchRawSize = 0x1200
$PatchedFileSize = $PatchSectionRawOffset + $PatchRawSize

[byte[]]$OriginalNumberOfSections = @(0x04, 0x00)
[byte[]]$PatchedNumberOfSections = @(0x05, 0x00)
[byte[]]$OriginalSizeOfImage = @(0x00, 0xE0, 0x40, 0x00)
[byte[]]$PatchedSizeOfImage = @(0x00, 0x00, 0x41, 0x00)
[byte[]]$OriginalLoadCall = @(0xE8, 0xAB, 0xCA, 0x0A, 0x00)
[byte[]]$OriginalSaveCall = @(0xE8, 0xA5, 0x07, 0x00, 0x00)

function New-RelativeCallBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE8
    [BitConverter]::GetBytes($relative).CopyTo($result, 1)
    return $result
}

[byte[]]$PatchedSaveCall = New-RelativeCallBytes $SaveCallVa $PatchSectionVa
[byte[]]$PatchedLoadCall = New-RelativeCallBytes $LoadCallVa ($PatchSectionVa + 0x300)

function New-SectionHeader {
    $bytes = New-Object byte[] 40
    [Text.Encoding]::ASCII.GetBytes(".mpst").CopyTo($bytes, 0)
    [BitConverter]::GetBytes([uint32]$PatchVirtualSize).CopyTo($bytes, 8)
    [BitConverter]::GetBytes([uint32]$PatchSectionRva).CopyTo($bytes, 12)
    [BitConverter]::GetBytes([uint32]$PatchRawSize).CopyTo($bytes, 16)
    [BitConverter]::GetBytes([uint32]$PatchSectionRawOffset).CopyTo($bytes, 20)
    [BitConverter]::GetBytes([uint32]0x60000020).CopyTo($bytes, 36)
    return $bytes
}

[byte[]]$PatchSectionHeader = New-SectionHeader

function New-PatchBlob {
    $bytes = New-Object byte[] $PatchRawSize

    function Set-Bytes {
        param([int]$Offset, [byte[]]$Patch)
        for ($i = 0; $i -lt $Patch.Length; $i++) {
            $bytes[$Offset + $i] = $Patch[$i]
        }
    }

    function Set-AsciiZ {
        param([int]$Offset, [string]$Text)
        $raw = [Text.Encoding]::ASCII.GetBytes($Text)
        Set-Bytes $Offset $raw
        $bytes[$Offset + $raw.Length] = 0
    }

    Set-Bytes 0x00 ([byte[]]@(
        0xE8, 0x3B, 0x75, 0xD1, 0xFF,       # call original Mods OK handler
        0x60,                               # pushad
        0x68, 0xA8, 0xE1, 0x80, 0x00,       # push "wb"
        0x68, 0x80, 0xE1, 0x80, 0x00,       # push "MajestyModPersistence.txt"
        0xFF, 0x15, 0x30, 0x54, 0x73, 0x00, # call fopen
        0x83, 0xC4, 0x08,                   # add esp, 8
        0x85, 0xC0,                         # test eax, eax
        0x74, 0x6B,                         # je done
        0x89, 0xC3,                         # mov ebx, eax
        0x8B, 0x35, 0x4C, 0x1E, 0x7C, 0x00, # mov esi, [active-list sentinel]
        0x85, 0xF6,                         # test esi, esi
        0x74, 0x55,                         # je close_file
        0x8B, 0x3E,                         # mov edi, [esi]
        0x39, 0xF7,                         # cmp edi, esi
        0x74, 0x4F,                         # je close_file
        0x8B, 0x47, 0x08,                   # mov eax, [edi+8]
        0x85, 0xC0,                         # test eax, eax
        0x74, 0x44,                         # je next_node
        0x0F, 0xB6, 0x48, 0x13,             # movzx ecx, byte ptr [eax+0x13]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x12,             # movzx ecx, byte ptr [eax+0x12]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x11,             # movzx ecx, byte ptr [eax+0x11]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x10,             # movzx ecx, byte ptr [eax+0x10]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0F,             # movzx ecx, byte ptr [eax+0x0f]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0E,             # movzx ecx, byte ptr [eax+0x0e]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0D,             # movzx ecx, byte ptr [eax+0x0d]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0C,             # movzx ecx, byte ptr [eax+0x0c]
        0x51,                               # push ecx
        0x0F, 0xB7, 0x48, 0x0A,             # movzx ecx, word ptr [eax+0x0a]
        0x51,                               # push ecx
        0x0F, 0xB7, 0x48, 0x08,             # movzx ecx, word ptr [eax+0x08]
        0x51,                               # push ecx
        0xFF, 0x70, 0x04,                   # push [eax+0x04]
        0x68, 0xAB, 0xE1, 0x80, 0x00,       # push "%s\r\n"
        0x53,                               # push ebx
        0xFF, 0x15, 0xE0, 0x53, 0x73, 0x00, # call fprintf
        0x83, 0xC4, 0x34,                   # add esp, 52
        0x8B, 0x3F,                         # mov edi, [edi]
        0xEB, 0xAD,                         # jmp loop_start
        0x53,                               # push ebx
        0xFF, 0x15, 0x44, 0x54, 0x73, 0x00, # call fclose
        0x83, 0xC4, 0x04,                   # add esp, 4
        0x61,                               # popad
        0xC3                                # ret
    ))

    Set-Bytes 0x300 ([byte[]]@(
        0xE8, 0xDB, 0x70, 0xD1, 0xFF,       # call original main-menu mod load handler
        0x60,                               # pushad
        0x68, 0xF0, 0xE1, 0x80, 0x00,       # push "rb"
        0x68, 0x80, 0xE1, 0x80, 0x00,       # push "MajestyModPersistence.txt"
        0xFF, 0x15, 0x30, 0x54, 0x73, 0x00, # call fopen
        0x83, 0xC4, 0x08,
        0x85, 0xC0,
        0x0F, 0x84, 0xC5, 0x01, 0x00, 0x00,
        0x89, 0xC3,
        0x53,
        0x68, 0xFF, 0x03, 0x00, 0x00,
        0x6A, 0x01,
        0x68, 0x00, 0xE7, 0x80, 0x00,
        0xFF, 0x15, 0x34, 0x54, 0x73, 0x00, # call fread
        0x83, 0xC4, 0x10,
        0x89, 0xC6,
        0x53,
        0xFF, 0x15, 0x44, 0x54, 0x73, 0x00, # call fclose
        0x83, 0xC4, 0x04,
        0x85, 0xF6,
        0x0F, 0x84, 0x99, 0x01, 0x00, 0x00,
        0xC6, 0x86, 0x00, 0xE7, 0x80, 0x00, 0x00,
        0xB9, 0x38, 0x1E, 0x7C, 0x00,
        0xE8, 0x42, 0x3A, 0xD1, 0xFF,       # call clear active list
        0xBE, 0x00, 0xE7, 0x80, 0x00,
        0x8A, 0x06,
        0x84, 0xC0,
        0x0F, 0x84, 0x79, 0x01, 0x00, 0x00,
        0x3C, 0x20,
        0x77, 0x03,
        0x46,
        0xEB, 0xEF,
        0x8D, 0x05, 0x88, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x84, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x80, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x7C, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x78, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x74, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x70, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x6C, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x68, 0xE2, 0x80, 0x00,
        0x50,
        0x8D, 0x05, 0x64, 0xE2, 0x80, 0x00,
        0x50,
        0x68, 0x60, 0xE2, 0x80, 0x00,
        0x68, 0x00, 0xE2, 0x80, 0x00,
        0x56,
        0xFF, 0x15, 0x4C, 0x54, 0x73, 0x00, # call sscanf
        0x83, 0xC4, 0x34,
        0x83, 0xF8, 0x0B,
        0x0F, 0x85, 0xF8, 0x00, 0x00, 0x00,
        0x8B, 0x15, 0x30, 0x1E, 0x7C, 0x00,
        0x8B, 0x3A,
        0x39, 0xD7,
        0x0F, 0x84, 0xE8, 0x00, 0x00, 0x00,
        0x8B, 0x47, 0x08,
        0x85, 0xC0,
        0x0F, 0x84, 0xD6, 0x00, 0x00, 0x00,
        0x8B, 0x0D, 0x60, 0xE2, 0x80, 0x00,
        0x39, 0x48, 0x04,
        0x0F, 0x85, 0xC7, 0x00, 0x00, 0x00,
        0x0F, 0xB7, 0x48, 0x08,
        0x3B, 0x0D, 0x64, 0xE2, 0x80, 0x00,
        0x0F, 0x85, 0xB7, 0x00, 0x00, 0x00,
        0x0F, 0xB7, 0x48, 0x0A,
        0x3B, 0x0D, 0x68, 0xE2, 0x80, 0x00,
        0x0F, 0x85, 0xA7, 0x00, 0x00, 0x00,
        0x0F, 0xB6, 0x48, 0x0C,
        0x3B, 0x0D, 0x6C, 0xE2, 0x80, 0x00,
        0x0F, 0x85, 0x97, 0x00, 0x00, 0x00,
        0x0F, 0xB6, 0x48, 0x0D,
        0x3B, 0x0D, 0x70, 0xE2, 0x80, 0x00,
        0x0F, 0x85, 0x87, 0x00, 0x00, 0x00,
        0x0F, 0xB6, 0x48, 0x0E,
        0x3B, 0x0D, 0x74, 0xE2, 0x80, 0x00,
        0x75, 0x7B,
        0x0F, 0xB6, 0x48, 0x0F,
        0x3B, 0x0D, 0x78, 0xE2, 0x80, 0x00,
        0x75, 0x6F,
        0x0F, 0xB6, 0x48, 0x10,
        0x3B, 0x0D, 0x7C, 0xE2, 0x80, 0x00,
        0x75, 0x63,
        0x0F, 0xB6, 0x48, 0x11,
        0x3B, 0x0D, 0x80, 0xE2, 0x80, 0x00,
        0x75, 0x57,
        0x0F, 0xB6, 0x48, 0x12,
        0x3B, 0x0D, 0x84, 0xE2, 0x80, 0x00,
        0x75, 0x4B,
        0x0F, 0xB6, 0x48, 0x13,
        0x3B, 0x0D, 0x88, 0xE2, 0x80, 0x00,
        0x75, 0x3F,
        0xA3, 0x8C, 0xE2, 0x80, 0x00,
        0xA1, 0x4C, 0x1E, 0x7C, 0x00,
        0x8B, 0x50, 0x04,
        0x8D, 0x58, 0x04,
        0x68, 0x8C, 0xE2, 0x80, 0x00,
        0x52,
        0x50,
        0xB9, 0x38, 0x1E, 0x7C, 0x00,
        0xE8, 0x96, 0x3E, 0xD1, 0xFF,
        0x6A, 0x01,
        0xB9, 0x38, 0x1E, 0x7C, 0x00,
        0x89, 0xC5,
        0xE8, 0x38, 0x3F, 0xD1, 0xFF,
        0x89, 0x2B,
        0x8B, 0x45, 0x04,
        0x89, 0x28,
        0xC6, 0x05, 0xFC, 0x1D, 0x7C, 0x00, 0x01,
        0xEB, 0x07,
        0x8B, 0x3F,
        0xE9, 0x10, 0xFF, 0xFF, 0xFF,
        0x8A, 0x06,
        0x84, 0xC0,
        0x74, 0x11,
        0x3C, 0x0A,
        0x74, 0x07,
        0x3C, 0x0D,
        0x74, 0x03,
        0x46,
        0xEB, 0xEF,
        0x46,
        0xE9, 0x7D, 0xFE, 0xFF, 0xFF,
        0x61,
        0xC3
    ))

    # Load hook restore build. It reads saved GUIDs, finds matching installed
    # mods, and appends them to Majesty's Active list after startup. It first
    # checks the Active list so repeated startup/menu calls do not duplicate
    # the same mod in memory or in the saved preset file.
    Set-Bytes 0x300 ([Convert]::FromBase64String("/3QkCP90JAjo03DR/4PECGBo8OGAAGiA4YAA/xUwVHMAg8QIhcAPhAgCAACJw1No/wMAAGoBaADZewD/FTRUcwCDxBCJxlP/FURUcwCDxASF9g+E3AEAAMaGANl7AAC+ANl7AIoGhMAPhMYBAAA8IHcGRuns////aCjdewBoJN17AGgg3XsAaBzdewBoGN17AGgU3XsAaBDdewBoDN17AGgI3XsAaATdewBoAN17AGgA4oAAVv8VTFRzAIPENIP4Cw+FTwEAAIsVMB58AIXSD4RBAQAAizo51w+ENwEAAItHCIXAD4QlAQAAiw0A3XsAOUgED4UWAQAAD7dICDsNBN17AA+FBgEAAA+3SAo7DQjdewAPhfYAAAAPtkgMOw0M3XsAD4XmAAAAD7ZIDTsNEN17AA+F1gAAAA+2SA47DRTdewAPhcYAAAAPtkgPOw0Y3XsAD4W2AAAAD7ZIEDsNHN17AA+FpgAAAA+2SBE7DSDdewAPhZYAAAAPtkgSOw0k3XsAD4WGAAAAD7ZIEzsNKN17AA+FdgAAAKMs3XsAVosNTB58AIXJD4QcAAAAizk5zw+EEgAAAItXCDnQD4RHAAAAiz/p5v///6FMHnwAhcAPhDMAAACLUASNWARoLN17AFJQuTgefADoUz7R/2oBuTgefACJxej1PtH/iSuLRQSJKMYF/B18AAFe6QcAAACLP+nB/v//igaEwA+EFAAAADwKdAo8DXQGRuno////Rukw/v//YcM="))

    Set-AsciiZ 0x180 "MajestyModPersistence.txt"
    Set-AsciiZ 0x1A8 "wb"
    Set-AsciiZ 0x1AB "%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X`r`n"
    Set-AsciiZ 0x1F0 "rb"
    Set-AsciiZ 0x200 "%8x-%4x-%4x-%2x%2x-%2x%2x%2x%2x%2x%2x"

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

$patchBlob = New-PatchBlob
$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$backupDir = Join-Path $resolvedGamePath $BackupDirName
$backupPath = Join-Path $backupDir "MajestyHD.exe.original"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)

$sectionsAlreadyPatched = Test-BytesEqual $bytes $NumberOfSectionsOffset $PatchedNumberOfSections
$sectionsAreStock = Test-BytesEqual $bytes $NumberOfSectionsOffset $OriginalNumberOfSections
$imageAlreadyPatched = Test-BytesEqual $bytes $SizeOfImageOffset $PatchedSizeOfImage
$imageIsStock = Test-BytesEqual $bytes $SizeOfImageOffset $OriginalSizeOfImage
$headerAlreadyPatched = Test-BytesEqual $bytes $NewSectionHeaderOffset $PatchSectionHeader
$headerSlotIsEmpty = Test-ZeroRange $bytes $NewSectionHeaderOffset 40
$loadAlreadyPatched = Test-BytesEqual $bytes $LoadCallOffset $PatchedLoadCall
$loadIsStock = Test-BytesEqual $bytes $LoadCallOffset $OriginalLoadCall
$saveAlreadyPatched = Test-BytesEqual $bytes $SaveCallOffset $PatchedSaveCall
$saveIsStock = Test-BytesEqual $bytes $SaveCallOffset $OriginalSaveCall
$blobAlreadyPatched = Test-BytesEqual $bytes $PatchSectionRawOffset $patchBlob

if (-not $sectionsAlreadyPatched -and -not $sectionsAreStock) {
    throw "MajestyHD.exe has an unexpected section count. Refusing to add a patch section."
}
if (-not $imageAlreadyPatched -and -not $imageIsStock) {
    throw "MajestyHD.exe has an unexpected image size. Refusing to add a patch section."
}
if (-not $headerAlreadyPatched -and -not $headerSlotIsEmpty) {
    throw ("The PE header slot at file offset 0x{0:X} is not empty. Refusing to add a patch section." -f $NewSectionHeaderOffset)
}
if (-not $saveAlreadyPatched -and -not $saveIsStock) {
    throw ("MajestyHD.exe is not the expected Steam build near file offset 0x{0:X}, or another patch already owns the mod-save hook." -f $SaveCallOffset)
}
if (-not $loadAlreadyPatched -and -not $loadIsStock) {
    throw ("MajestyHD.exe is not the expected Steam build near file offset 0x{0:X}, or another patch already owns the mod-load hook." -f $LoadCallOffset)
}
if ($sectionsAreStock -and $bytes.Length -ne $PatchSectionRawOffset) {
    throw ("MajestyHD.exe has an unexpected file size 0x{0:X}. Expected 0x{1:X} before appending the patch section." -f $bytes.Length, $PatchSectionRawOffset)
}
if ($sectionsAlreadyPatched -and $bytes.Length -ne $PatchedFileSize) {
    throw ("MajestyHD.exe already has the mod persistence section, but its file size is 0x{0:X}. Expected 0x{1:X}." -f $bytes.Length, $PatchedFileSize)
}

Write-Host "Majesty Gold HD Mod Persistence installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Preset file: MajestyModPersistence.txt"
Write-Host "Mode: remember Active mods across launches"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($sectionsAlreadyPatched -and $imageAlreadyPatched -and $headerAlreadyPatched -and $saveAlreadyPatched -and $loadAlreadyPatched -and $blobAlreadyPatched) {
    Write-Host "MajestyHD.exe: Remember Active Mods is already installed."
    return
}

if ($DryRun) {
    if (-not $sectionsAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would add .mpst section header at file offset 0x{0:X}." -f $NewSectionHeaderOffset)
        Write-Host ("MajestyHD.exe: would append .mpst section data at file offset 0x{0:X}." -f $PatchSectionRawOffset)
    } else {
        Write-Host ("MajestyHD.exe: would update existing .mpst section data at file offset 0x{0:X}." -f $PatchSectionRawOffset)
    }
    if (-not $saveAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch mod-save hook at file offset 0x{0:X}." -f $SaveCallOffset)
    }
    if (-not $loadAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch mod-load hook at file offset 0x{0:X}." -f $LoadCallOffset)
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

$patchedBytes = New-Object byte[] $PatchedFileSize
[Array]::Copy($bytes, 0, $patchedBytes, 0, $bytes.Length)

Write-Bytes $patchedBytes $NumberOfSectionsOffset $PatchedNumberOfSections
Write-Bytes $patchedBytes $SizeOfImageOffset $PatchedSizeOfImage
Write-Bytes $patchedBytes $NewSectionHeaderOffset $PatchSectionHeader
Write-Bytes $patchedBytes $SaveCallOffset $PatchedSaveCall
Write-Bytes $patchedBytes $LoadCallOffset $PatchedLoadCall
Write-Bytes $patchedBytes $PatchSectionRawOffset $patchBlob

[IO.File]::WriteAllBytes($exePath, $patchedBytes)

Write-Host "Done. Majesty should now remember the mods in the Active list across launches."
Write-Host "Use Uninstall - Restore Stock Mod Selection.bat to restore stock behavior."
