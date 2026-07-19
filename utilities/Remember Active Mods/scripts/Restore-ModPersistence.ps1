param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"

$NumberOfSectionsOffset = 0x10E
$SizeOfImageOffset = 0x158
$NewSectionHeaderOffset = 0x2A0
$LoadCallOffset = 0x77D30
$LoadCallVa = 0x478930
$SaveCallOffset = 0x124196
$SaveCallVa = 0x524D96

$PatchSectionRawOffset = 0x3C0600
$PatchSectionVa = 0x80E000
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
    [BitConverter]::GetBytes([uint32]0x11AF).CopyTo($bytes, 8)
    [BitConverter]::GetBytes([uint32]0x40E000).CopyTo($bytes, 12)
    [BitConverter]::GetBytes([uint32]$PatchRawSize).CopyTo($bytes, 16)
    [BitConverter]::GetBytes([uint32]$PatchSectionRawOffset).CopyTo($bytes, 20)
    [BitConverter]::GetBytes([uint32]0x60000020).CopyTo($bytes, 36)
    return $bytes
}

[byte[]]$PatchSectionHeader = New-SectionHeader

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

$sectionsArePatched = Test-BytesEqual $bytes $NumberOfSectionsOffset $PatchedNumberOfSections
$sectionsAreStock = Test-BytesEqual $bytes $NumberOfSectionsOffset $OriginalNumberOfSections
$imageIsPatched = Test-BytesEqual $bytes $SizeOfImageOffset $PatchedSizeOfImage
$imageIsStock = Test-BytesEqual $bytes $SizeOfImageOffset $OriginalSizeOfImage
$headerIsPatched = Test-BytesEqual $bytes $NewSectionHeaderOffset $PatchSectionHeader
$loadIsPatched = Test-BytesEqual $bytes $LoadCallOffset $PatchedLoadCall
$loadIsStock = Test-BytesEqual $bytes $LoadCallOffset $OriginalLoadCall
$saveIsPatched = Test-BytesEqual $bytes $SaveCallOffset $PatchedSaveCall
$saveIsStock = Test-BytesEqual $bytes $SaveCallOffset $OriginalSaveCall

$isInstalled = $sectionsArePatched -or $imageIsPatched -or $headerIsPatched -or $saveIsPatched -or $loadIsPatched

Write-Host "Majesty Gold HD Mod Persistence restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if (-not $isInstalled) {
    if ($sectionsAreStock -and $imageIsStock -and $saveIsStock -and $loadIsStock) {
        Write-Host "MajestyHD.exe: mod persistence is not installed."
        return
    }
    throw "MajestyHD.exe does not match the expected installed or stock mod persistence bytes."
}

if (-not ($sectionsArePatched -and $imageIsPatched -and $headerIsPatched -and $saveIsPatched)) {
    throw "MajestyHD.exe has only part of the mod persistence section patch. Refusing to restore automatically."
}
if ($bytes.Length -ne $PatchedFileSize) {
    throw ("MajestyHD.exe has unexpected patched file size 0x{0:X}. Refusing to truncate automatically." -f $bytes.Length)
}

if ($DryRun) {
    Write-Host ("MajestyHD.exe: would restore mod-save hook at file offset 0x{0:X}." -f $SaveCallOffset)
    if ($loadIsPatched) {
        Write-Host ("MajestyHD.exe: would restore mod-load hook at file offset 0x{0:X}." -f $LoadCallOffset)
    }
    Write-Host ("MajestyHD.exe: would remove .mpst section header at file offset 0x{0:X}." -f $NewSectionHeaderOffset)
    Write-Host ("MajestyHD.exe: would truncate appended .mpst data back to file offset 0x{0:X}." -f $PatchSectionRawOffset)
    return
}

Assert-FileWritable $exePath

$restoredBytes = New-Object byte[] $PatchSectionRawOffset
[Array]::Copy($bytes, 0, $restoredBytes, 0, $PatchSectionRawOffset)

Write-Bytes $restoredBytes $NumberOfSectionsOffset $OriginalNumberOfSections
Write-Bytes $restoredBytes $SizeOfImageOffset $OriginalSizeOfImage
Write-Bytes $restoredBytes $NewSectionHeaderOffset (New-Object byte[] 40)
Write-Bytes $restoredBytes $SaveCallOffset $OriginalSaveCall
if ($loadIsPatched) {
    Write-Bytes $restoredBytes $LoadCallOffset $OriginalLoadCall
}

[IO.File]::WriteAllBytes($exePath, $restoredBytes)

Write-Host "Done. Majesty's stock mod selection behavior is restored."
