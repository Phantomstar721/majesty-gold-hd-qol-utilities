param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"

$SectionName = ".mpst"
$LoadCallOffset = 0x77D30
$LoadCallVa = 0x478930
$SaveCallOffset = 0x124196
$SaveCallVa = 0x524D96

$PatchRawSize = 0x1200

[byte[]]$OriginalLoadCall = @(0xE8, 0xAB, 0xCA, 0x0A, 0x00)
[byte[]]$OriginalSaveCall = @(0xE8, 0xA5, 0x07, 0x00, 0x00)

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

function Test-ZeroRange {
    param([byte[]]$Bytes, [int]$Offset, [int]$Length)
    if ($Offset -lt 0 -or ($Offset + $Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Length; $i++) {
        if ($Bytes[$Offset + $i] -ne 0) { return $false }
    }
    return $true
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

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)

$pe = Get-PeInfo $bytes
$section = $pe.Sections | Where-Object { $_.Name -eq $SectionName } | Select-Object -First 1

$loadIsStock = Test-BytesEqual $bytes $LoadCallOffset $OriginalLoadCall
$saveIsStock = Test-BytesEqual $bytes $SaveCallOffset $OriginalSaveCall

Write-Host "Majesty Gold HD Mod Persistence restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if (-not $section) {
    if ($saveIsStock -and $loadIsStock) {
        Write-Host "MajestyHD.exe: mod persistence is not installed."
        return
    }
    throw "MajestyHD.exe does not match the expected installed or stock mod persistence bytes."
}

$patchSectionVa = [uint32]($pe.ImageBase + $section.Rva)
[byte[]]$PatchedSaveCall = New-RelativeCallBytes $SaveCallVa $patchSectionVa
[byte[]]$PatchedLoadCall = New-RelativeCallBytes $LoadCallVa ($patchSectionVa + 0x300)
$loadIsPatched = Test-BytesEqual $bytes $LoadCallOffset $PatchedLoadCall
$saveIsPatched = Test-BytesEqual $bytes $SaveCallOffset $PatchedSaveCall
$sectionIsLast = ($section.Index -eq ($pe.SectionCount - 1)) -and
                 ($bytes.Length -eq ($section.RawOffset + $PatchRawSize))
$sectionIsInert = Test-ZeroRange $bytes $section.RawOffset $PatchRawSize

if ($saveIsStock -and $loadIsStock -and $sectionIsInert -and -not $sectionIsLast) {
    Write-Host "MajestyHD.exe: Remember Active Mods is already uninstalled; its inert private section is reserved for safe reuse."
    return
}
if (-not (($saveIsPatched -and $loadIsPatched) -or ($saveIsStock -and $loadIsStock -and $sectionIsInert))) {
    throw "MajestyHD.exe has only part of the mod persistence section patch. Refusing to restore automatically."
}

if ($sectionIsLast) {
    $previousSection = $pe.Sections | Where-Object { $_.Index -eq ($section.Index - 1) } | Select-Object -First 1
    $restoredSizeOfImage = Align-Value ([uint32]($previousSection.Rva + [Math]::Max($previousSection.VirtualSize, $previousSection.RawSize))) ([uint32]$pe.SectionAlignment)
}

if ($DryRun) {
    Write-Host ("MajestyHD.exe: would restore mod-save hook at file offset 0x{0:X}." -f $SaveCallOffset)
    if ($loadIsPatched) {
        Write-Host ("MajestyHD.exe: would restore mod-load hook at file offset 0x{0:X}." -f $LoadCallOffset)
    }
    if ($sectionIsLast) {
        Write-Host ("MajestyHD.exe: would remove .mpst section header at file offset 0x{0:X}." -f $section.HeaderOffset)
        Write-Host ("MajestyHD.exe: would truncate appended .mpst data back to file offset 0x{0:X}." -f $section.RawOffset)
    } else {
        Write-Host "MajestyHD.exe: would leave the now-inert .mpst section in place because later patch sections depend on the current PE layout."
    }
    return
}

Assert-FileWritable $exePath

$restoredLength = if ($sectionIsLast) { [int]$section.RawOffset } else { $bytes.Length }
$restoredBytes = New-Object byte[] $restoredLength
[Array]::Copy($bytes, 0, $restoredBytes, 0, $restoredLength)

if ($sectionIsLast) {
    [BitConverter]::GetBytes([uint16]($pe.SectionCount - 1)).CopyTo($restoredBytes, $pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$restoredSizeOfImage).CopyTo($restoredBytes, $pe.SizeOfImageOffset)
    Write-Bytes $restoredBytes $section.HeaderOffset (New-Object byte[] 40)
} else {
    Write-Bytes $restoredBytes $section.RawOffset (New-Object byte[] $PatchRawSize)
}
Write-Bytes $restoredBytes $SaveCallOffset $OriginalSaveCall
Write-Bytes $restoredBytes $LoadCallOffset $OriginalLoadCall

[IO.File]::WriteAllBytes($exePath, $restoredBytes)

Write-Host "Done. Majesty's stock mod selection behavior is restored."
