param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$SectionName = ".mgvl"
$SectionCharacteristics = 1610612768
$PatchVirtualSize = 0x64
$PatchRawSize = 0x200
$GateOffset = 0x979D5
$IconDispatchOffset = 0x97818
$IconCodeCaveOffset = 0x33439D
$ThreatDispatchOffset = 0x97AD1
$ThreatDispatchVa = 0x4986D1
$DisplayClassifierVa = 0x508510
$AttributeGetterVa = 0x5B9FD0

[byte[]]$OriginalGateBytes = @(0x0F, 0x85, 0xB6, 0x04, 0x00, 0x00)
[byte[]]$PatchedGateBytes = @(0x0F, 0x85, 0xCA, 0x00, 0x00, 0x00)
[byte[]]$OriginalIconDispatchBytes = @(0x6A, 0x01, 0x8D, 0x8C, 0x24, 0xC4, 0x00, 0x00, 0x00)
[byte[]]$PatchedIconDispatchBytes = @(0xE9, 0x80, 0xCB, 0x29, 0x00, 0x90, 0x90, 0x90, 0x90)
[byte[]]$OriginalThreatDispatchBytes = @(0xE8, 0xFA, 0x18, 0x12, 0x00)
[byte[]]$IconDispatchPayload = @(
    0x57, 0xE8, 0x6D, 0x35, 0xDD, 0xFF, 0x83, 0xC4, 0x04, 0x83, 0xF8, 0x01, 0x74, 0x1E,
    0x83, 0xF8, 0x02, 0x74, 0x19, 0x8B, 0x47, 0x28, 0x50, 0x8D, 0x84, 0x24, 0xC4, 0x00,
    0x00, 0x00, 0x50, 0xE8, 0xDF, 0x60, 0xD8, 0xFF, 0x83, 0xC4, 0x08, 0xE9, 0xB4, 0x34,
    0xD6, 0xFF, 0x6A, 0x01, 0x8D, 0x8C, 0x24, 0xC4, 0x00, 0x00, 0x00, 0xE9, 0x4A, 0x34,
    0xD6, 0xFF
)
[byte[]]$EmptyIconCodeCave = New-Object byte[] $IconDispatchPayload.Length

function Read-U16 { param([byte[]]$Bytes, [int]$Offset) return [BitConverter]::ToUInt16($Bytes, $Offset) }
function Read-U32 { param([byte[]]$Bytes, [int]$Offset) return [BitConverter]::ToUInt32($Bytes, $Offset) }
function Align-Value {
    param([uint32]$Value, [uint32]$Alignment)
    return [uint32](([uint64][Math]::Ceiling([double]$Value / [double]$Alignment)) * $Alignment)
}
function Test-BytesEqual {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected)
    if ($Offset -lt 0 -or ($Offset + $Expected.Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) { if ($Bytes[$Offset + $i] -ne $Expected[$i]) { return $false } }
    return $true
}
function Test-ZeroRange {
    param([byte[]]$Bytes, [int]$Offset, [int]$Length)
    if ($Offset -lt 0 -or ($Offset + $Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Length; $i++) { if ($Bytes[$Offset + $i] -ne 0) { return $false } }
    return $true
}
function Write-Bytes {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Patch)
    if ($Offset -lt 0 -or ($Offset + $Patch.Length) -gt $Bytes.Length) { throw "Restore range at 0x$($Offset.ToString('X')) is outside MajestyHD.exe." }
    [Array]::Copy($Patch, 0, $Bytes, $Offset, $Patch.Length)
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
        $sections += [pscustomobject]@{
            Index = $i; HeaderOffset = $off
            Name = [Text.Encoding]::ASCII.GetString($Bytes[$off..($off + 7)]).TrimEnd([char]0)
            VirtualSize = Read-U32 $Bytes ($off + 8); Rva = Read-U32 $Bytes ($off + 12)
            RawSize = Read-U32 $Bytes ($off + 16); RawOffset = Read-U32 $Bytes ($off + 20)
            Characteristics = Read-U32 $Bytes ($off + 36)
        }
    }
    return [pscustomobject]@{
        SectionCountOffset = $sectionCountOffset; SectionCount = $sectionCount
        ImageBase = Read-U32 $Bytes ($optionalHeaderOffset + 28)
        SectionAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 32)
        SizeOfImageOffset = $optionalHeaderOffset + 56
        Sections = $sections
    }
}
function New-SectionHeader {
    param([string]$Name, [uint32]$VirtualSize, [uint32]$Rva, [uint32]$RawSize, [uint32]$RawOffset)
    [byte[]]$result = New-Object byte[] 40
    [Text.Encoding]::ASCII.GetBytes($Name).CopyTo($result, 0)
    [BitConverter]::GetBytes($VirtualSize).CopyTo($result, 8)
    [BitConverter]::GetBytes($Rva).CopyTo($result, 12)
    [BitConverter]::GetBytes($RawSize).CopyTo($result, 16)
    [BitConverter]::GetBytes($RawOffset).CopyTo($result, 20)
    [BitConverter]::GetBytes([uint32]$SectionCharacteristics).CopyTo($result, 36)
    return $result
}
function New-RelativeInstruction {
    param([byte]$Opcode, [uint32]$SourceVa, [uint32]$TargetVa)
    [byte[]]$result = New-Object byte[] 5
    $result[0] = $Opcode
    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    [BitConverter]::GetBytes($relative).CopyTo($result, 1)
    return $result
}
function New-ThreatRankBlob {
    param([uint32]$PatchVa)
    [byte[]]$blob = New-Object byte[] $PatchRawSize
    [byte[]]$code = @(
        0x57, 0xE8, 0, 0, 0, 0, 0x83, 0xC4, 0x04, 0x83, 0xF8, 0x01, 0x74, 0x33,
        0x83, 0xF8, 0x02, 0x74, 0x2E, 0x6A, 0x00, 0x68, 0x41, 0x50, 0x56, 0x0A, 0x8B, 0xCF,
        0xE8, 0, 0, 0, 0, 0x85, 0xC0, 0x7E, 0x1C, 0xBA, 0x01, 0x00, 0x00, 0x00,
        0xB9, 0, 0, 0, 0, 0x3B, 0x01, 0x7E, 0x09, 0x42, 0x83, 0xC1, 0x04, 0x83,
        0xFA, 0x08, 0x7C, 0xF3, 0x8B, 0xC2, 0xC2, 0x08, 0x00, 0x8B, 0xCF, 0xE9, 0, 0,
        0, 0, 0xE6, 0x00, 0x00, 0x00, 0x90, 0x01, 0x00, 0x00, 0xF4, 0x01, 0x00, 0x00,
        0x84, 0x03, 0x00, 0x00, 0xDC, 0x05, 0x00, 0x00, 0xD0, 0x07, 0x00, 0x00, 0xAC, 0x0D,
        0x00, 0x00
    )
    Write-Bytes $code 0x01 (New-RelativeInstruction 0xE8 ([uint32]($PatchVa + 0x01)) $DisplayClassifierVa)
    Write-Bytes $code 0x1C (New-RelativeInstruction 0xE8 ([uint32]($PatchVa + 0x1C)) $AttributeGetterVa)
    [BitConverter]::GetBytes([uint32]($PatchVa + 0x48)).CopyTo($code, 0x2B)
    Write-Bytes $code 0x43 (New-RelativeInstruction 0xE9 ([uint32]($PatchVa + 0x43)) $AttributeGetterVa)
    Write-Bytes $blob 0 $code
    return $blob
}
function Get-MajestyPath {
    param([string]$RequestedPath)
    if ($RequestedPath) { return $RequestedPath }
    if (Test-Path -LiteralPath $DefaultGamePath) { return $DefaultGamePath }
    $appId = 73230
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam", "HKCU:\SOFTWARE\Valve\Steam")) {
        try { $path = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath; if ($path) { $roots.Add($path) } } catch {}
    }
    foreach ($root in @($roots)) {
        $candidate = Join-Path $root "steamapps\common\Majesty HD"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $library = $Matches[1] -replace '\\\\', '\'
                    $candidate = Join-Path $library "steamapps\common\Majesty HD"
                    if (Test-Path -LiteralPath $candidate) { return $candidate }
                }
            }
        }
    }
    throw "Could not find Majesty Gold HD. Re-run with -GamePath."
}
function Assert-FileWritable {
    param([string]$Path)
    $stream = $null
    try { $stream = [IO.File]::Open($Path, 'Open', 'ReadWrite', 'None') }
    catch { throw "Cannot modify MajestyHD.exe. Close Majesty and try again. If needed, run the BAT as administrator." }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
if (-not (Test-Path -LiteralPath $exePath)) { throw "Could not find MajestyHD.exe at $exePath." }
[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$pe = Get-PeInfo $bytes
$section = $pe.Sections | Where-Object Name -eq $SectionName | Select-Object -First 1

$isGateStock = Test-BytesEqual $bytes $GateOffset $OriginalGateBytes
$isGatePatched = Test-BytesEqual $bytes $GateOffset $PatchedGateBytes
$isIconStock = Test-BytesEqual $bytes $IconDispatchOffset $OriginalIconDispatchBytes
$isIconPatched = Test-BytesEqual $bytes $IconDispatchOffset $PatchedIconDispatchBytes
$isIconCaveEmpty = Test-BytesEqual $bytes $IconCodeCaveOffset $EmptyIconCodeCave
$isIconCavePatched = Test-BytesEqual $bytes $IconCodeCaveOffset $IconDispatchPayload
$isThreatStock = Test-BytesEqual $bytes $ThreatDispatchOffset $OriginalThreatDispatchBytes

if (-not $isGateStock -and -not $isGatePatched) { throw "Unexpected visitor-row category-gate bytes." }
if (-not $isIconStock -and -not $isIconPatched) { throw "Unexpected visitor-row icon bytes." }
if (-not $isIconCaveEmpty -and -not $isIconCavePatched) { throw "The visitor icon code cave contains unexpected data." }
if ($isIconStock -ne $isIconCaveEmpty) { throw "The visitor icon dispatch and payload are inconsistent." }

$isThreatPatched = $false
$blobPatched = $false
$blobEmpty = $false
$sectionIsLast = $false
if ($section) {
    $patchVa = [uint32]($pe.ImageBase + $section.Rva)
    $expectedHeader = New-SectionHeader $SectionName $PatchVirtualSize $section.Rva $PatchRawSize $section.RawOffset
    $expectedBlob = New-ThreatRankBlob $patchVa
    $patchedThreatDispatch = New-RelativeInstruction 0xE8 $ThreatDispatchVa $patchVa
    $isThreatPatched = Test-BytesEqual $bytes $ThreatDispatchOffset $patchedThreatDispatch
    $blobPatched = Test-BytesEqual $bytes $section.RawOffset $expectedBlob
    $blobEmpty = Test-ZeroRange $bytes $section.RawOffset $PatchRawSize
    if (-not (Test-BytesEqual $bytes $section.HeaderOffset $expectedHeader)) { throw "The .mgvl section header is not owned by Generic Visitor Lists." }
    if (-not $blobPatched -and -not $blobEmpty) { throw "The .mgvl section contains unexpected data." }
    if (-not $isThreatStock -and -not $isThreatPatched) { throw "The visitor-row level hook does not target .mgvl or stock." }
    if ($isThreatPatched -and -not $blobPatched) { throw "The visitor-row level hook targets an incomplete .mgvl section." }
    $sectionIsLast = ($section.Index -eq ($pe.SectionCount - 1)) -and ($bytes.Length -eq ($section.RawOffset + $PatchRawSize))
} elseif (-not $isThreatStock) {
    throw "The visitor-row level hook is patched, but no .mgvl section exists."
}

Write-Host "Majesty Gold HD Generic Visitor Lists restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($isGateStock -and $isIconStock -and $isIconCaveEmpty -and $isThreatStock -and
    (-not $section -or ($blobEmpty -and -not $sectionIsLast))) {
    Write-Host "MajestyHD.exe: stock visitor-list filtering is already present."
    return
}
if ($DryRun) {
    if ($isGatePatched) { Write-Host ("MajestyHD.exe: would restore the stock visitor-row gate at 0x{0:X}." -f $GateOffset) }
    if ($isIconPatched) { Write-Host ("MajestyHD.exe: would restore stock icon setup at 0x{0:X}." -f $IconDispatchOffset) }
    if ($isThreatPatched) { Write-Host ("MajestyHD.exe: would restore stock level lookup at 0x{0:X}." -f $ThreatDispatchOffset) }
    if ($sectionIsLast) { Write-Host "MajestyHD.exe: would remove the trailing .mgvl section." }
    elseif ($section -and $blobPatched) { Write-Host "MajestyHD.exe: would leave an inert .mgvl section because later patch sections depend on the current PE layout." }
    return
}

Assert-FileWritable $exePath
$restoredLength = if ($sectionIsLast) { [int]$section.RawOffset } else { $bytes.Length }
[byte[]]$restored = New-Object byte[] $restoredLength
[Array]::Copy($bytes, 0, $restored, 0, $restoredLength)
if ($sectionIsLast) {
    $previous = $pe.Sections | Where-Object Index -eq ($section.Index - 1) | Select-Object -First 1
    $restoredSizeOfImage = Align-Value ([uint32]($previous.Rva + [Math]::Max($previous.VirtualSize, $previous.RawSize))) ([uint32]$pe.SectionAlignment)
    [BitConverter]::GetBytes([uint16]($pe.SectionCount - 1)).CopyTo($restored, $pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$restoredSizeOfImage).CopyTo($restored, $pe.SizeOfImageOffset)
    Write-Bytes $restored $section.HeaderOffset (New-Object byte[] 40)
} elseif ($section -and $blobPatched) {
    Write-Bytes $restored $section.RawOffset (New-Object byte[] $PatchRawSize)
}
Write-Bytes $restored $GateOffset $OriginalGateBytes
Write-Bytes $restored $IconDispatchOffset $OriginalIconDispatchBytes
Write-Bytes $restored $IconCodeCaveOffset $EmptyIconCodeCave
Write-Bytes $restored $ThreatDispatchOffset $OriginalThreatDispatchBytes
[IO.File]::WriteAllBytes($exePath, $restored)

Write-Host "Done. Stock visitor-list filtering is restored; other Majesty QOL patches were left untouched."
