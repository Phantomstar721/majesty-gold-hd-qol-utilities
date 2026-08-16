param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$SectionName = ".mgvl"
$SectionCharacteristics = 1610612768
$PatchVirtualSize = 0xBA
$PatchRawSize = 0x200
$IconPayloadOffset = 0x80
$GateOffset = 0x979D5
$IconDispatchOffset = 0x97818
$IconDispatchVa = 0x498418
$ThreatDispatchOffset = 0x97AD1
$ThreatDispatchVa = 0x4986D1
$DisplayClassifierVa = 0x508510
$AttributeGetterVa = 0x5B9FD0
$MonsterResolverVa = 0x4BB0A0
$IconHeroResumeVa = 0x498421
$IconMonsterResumeVa = 0x49847D

[byte[]]$OriginalGateBytes = @(0x0F, 0x85, 0xB6, 0x04, 0x00, 0x00)
[byte[]]$PatchedGateBytes = @(0x0F, 0x85, 0xCA, 0x00, 0x00, 0x00)
[byte[]]$OriginalIconDispatchBytes = @(0x6A, 0x01, 0x8D, 0x8C, 0x24, 0xC4, 0x00, 0x00, 0x00)
[byte[]]$LegacyIconDispatchBytes = @(0xE9, 0x80, 0xCB, 0x29, 0x00, 0x90, 0x90, 0x90, 0x90)
[byte[]]$OriginalThreatDispatchBytes = @(0xE8, 0xFA, 0x18, 0x12, 0x00)
[byte[]]$LegacyIconPayload = @(
    0x57, 0xE8, 0x6D, 0x35, 0xDD, 0xFF, 0x83, 0xC4, 0x04, 0x83, 0xF8, 0x01, 0x74, 0x1E,
    0x83, 0xF8, 0x02, 0x74, 0x19, 0x8B, 0x47, 0x28, 0x50, 0x8D, 0x84, 0x24, 0xC4, 0x00,
    0x00, 0x00, 0x50, 0xE8, 0xDF, 0x60, 0xD8, 0xFF, 0x83, 0xC4, 0x08, 0xE9, 0xB4, 0x34,
    0xD6, 0xFF, 0x6A, 0x01, 0x8D, 0x8C, 0x24, 0xC4, 0x00, 0x00, 0x00, 0xE9, 0x4A, 0x34,
    0xD6, 0xFF
)
$LegacyIconCodeCaveOffset = 0x33439D

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
function New-IconDispatchPatch {
    param([uint32]$TargetVa)
    [byte[]]$result = New-Object byte[] 9
    Write-Bytes $result 0 (New-RelativeInstruction 0xE9 $IconDispatchVa $TargetVa)
    for ($i = 5; $i -lt $result.Length; $i++) { $result[$i] = 0x90 }
    return $result
}
function New-LegacyPatchBlob {
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
function New-PatchBlob {
    param([uint32]$PatchVa)
    [byte[]]$blob = New-LegacyPatchBlob $PatchVa
    [byte[]]$iconCode = @(
        0x57, 0xE8, 0, 0, 0, 0, 0x83, 0xC4, 0x04, 0x83, 0xF8, 0x01, 0x74, 0x1E,
        0x83, 0xF8, 0x02, 0x74, 0x19, 0x8B, 0x47, 0x28, 0x50, 0x8D, 0x84, 0x24, 0xC4, 0x00,
        0x00, 0x00, 0x50, 0xE8, 0, 0, 0, 0, 0x83, 0xC4, 0x08, 0xE9, 0, 0, 0, 0,
        0x6A, 0x01, 0x8D, 0x8C, 0x24, 0xC4, 0x00, 0x00, 0x00, 0xE9, 0, 0, 0, 0
    )
    $iconVa = [uint32]($PatchVa + $IconPayloadOffset)
    Write-Bytes $iconCode 0x01 (New-RelativeInstruction 0xE8 ([uint32]($iconVa + 0x01)) $DisplayClassifierVa)
    Write-Bytes $iconCode 0x1F (New-RelativeInstruction 0xE8 ([uint32]($iconVa + 0x1F)) $MonsterResolverVa)
    Write-Bytes $iconCode 0x27 (New-RelativeInstruction 0xE9 ([uint32]($iconVa + 0x27)) $IconMonsterResumeVa)
    Write-Bytes $iconCode 0x35 (New-RelativeInstruction 0xE9 ([uint32]($iconVa + 0x35)) $IconHeroResumeVa)
    Write-Bytes $blob $IconPayloadOffset $iconCode
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
$isIconPatched = $false
$isLegacyIconPatched = (Test-BytesEqual $bytes $IconDispatchOffset $LegacyIconDispatchBytes) -and
    (Test-BytesEqual $bytes $LegacyIconCodeCaveOffset $LegacyIconPayload)
$isThreatStock = Test-BytesEqual $bytes $ThreatDispatchOffset $OriginalThreatDispatchBytes

if (-not $isGateStock -and -not $isGatePatched) { throw "Unexpected visitor-row category-gate bytes." }

$isThreatPatched = $false
$blobPatched = $false
$legacyBlobPatched = $false
$blobEmpty = $false
$sectionIsLast = $false
if ($section) {
    $patchVa = [uint32]($pe.ImageBase + $section.Rva)
    $expectedHeader = New-SectionHeader $SectionName $PatchVirtualSize $section.Rva $PatchRawSize $section.RawOffset
    $legacyHeader = New-SectionHeader $SectionName 0x64 $section.Rva $PatchRawSize $section.RawOffset
    $expectedBlob = New-PatchBlob $patchVa
    $legacyBlob = New-LegacyPatchBlob $patchVa
    $patchedIconDispatch = New-IconDispatchPatch ([uint32]($patchVa + $IconPayloadOffset))
    $patchedThreatDispatch = New-RelativeInstruction 0xE8 $ThreatDispatchVa $patchVa
    $isIconPatched = Test-BytesEqual $bytes $IconDispatchOffset $patchedIconDispatch
    $isThreatPatched = Test-BytesEqual $bytes $ThreatDispatchOffset $patchedThreatDispatch
    $blobPatched = Test-BytesEqual $bytes $section.RawOffset $expectedBlob
    $legacyBlobPatched = Test-BytesEqual $bytes $section.RawOffset $legacyBlob
    $blobEmpty = Test-ZeroRange $bytes $section.RawOffset $PatchRawSize
    $headerOwned = (Test-BytesEqual $bytes $section.HeaderOffset $expectedHeader) -or
        (Test-BytesEqual $bytes $section.HeaderOffset $legacyHeader)
    if (-not $headerOwned) { throw "The .mgvl section header is not owned by Generic Visitor Lists." }
    if (-not $blobPatched -and -not $legacyBlobPatched -and -not $blobEmpty) { throw "The .mgvl section contains unexpected data." }
    if (-not $isThreatStock -and -not $isThreatPatched) { throw "The visitor-row level hook does not target .mgvl or stock." }
    if ($isThreatPatched -and -not $blobPatched -and -not $legacyBlobPatched) { throw "The visitor-row level hook targets an incomplete .mgvl section." }
    if ($isIconPatched -and -not $blobPatched) { throw "The visitor-row icon hook targets an incomplete .mgvl section." }
    if ($isLegacyIconPatched -and -not $legacyBlobPatched) { throw "The legacy visitor-row icon hook is incomplete." }
    $sectionIsLast = ($section.Index -eq ($pe.SectionCount - 1)) -and ($bytes.Length -eq ($section.RawOffset + $PatchRawSize))
} elseif (-not $isThreatStock -or -not $isIconStock) {
    throw "A visitor-row hook is patched, but no .mgvl section exists."
}
if (-not $isIconStock -and -not $isIconPatched -and -not $isLegacyIconPatched) { throw "Unexpected visitor-row icon bytes." }

Write-Host "Majesty Gold HD Generic Visitor Lists restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($isGateStock -and $isIconStock -and $isThreatStock -and
    (-not $section -or ($blobEmpty -and -not $sectionIsLast))) {
    Write-Host "MajestyHD.exe: stock visitor-list filtering is already present."
    return
}
if ($DryRun) {
    if ($isGatePatched) { Write-Host ("MajestyHD.exe: would restore the stock visitor-row gate at 0x{0:X}." -f $GateOffset) }
    if ($isIconPatched -or $isLegacyIconPatched) { Write-Host ("MajestyHD.exe: would restore stock icon setup at 0x{0:X}." -f $IconDispatchOffset) }
    if ($isThreatPatched) { Write-Host ("MajestyHD.exe: would restore stock level lookup at 0x{0:X}." -f $ThreatDispatchOffset) }
    if ($sectionIsLast) { Write-Host "MajestyHD.exe: would remove the trailing .mgvl section." }
    elseif ($section -and ($blobPatched -or $legacyBlobPatched)) { Write-Host "MajestyHD.exe: would leave an inert .mgvl section because later patch sections depend on the current PE layout." }
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
} elseif ($section -and ($blobPatched -or $legacyBlobPatched)) {
    Write-Bytes $restored $section.RawOffset (New-Object byte[] $PatchRawSize)
}
Write-Bytes $restored $GateOffset $OriginalGateBytes
Write-Bytes $restored $IconDispatchOffset $OriginalIconDispatchBytes
if ($isLegacyIconPatched) { Write-Bytes $restored $LegacyIconCodeCaveOffset (New-Object byte[] $LegacyIconPayload.Length) }
Write-Bytes $restored $ThreatDispatchOffset $OriginalThreatDispatchBytes
[IO.File]::WriteAllBytes($exePath, $restored)

Write-Host "Done. Stock visitor-list filtering is restored; other Majesty QOL patches were left untouched."
