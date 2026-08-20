param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "MajestyBuildProfiles.ps1")

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_generic_visitor_lists_originals"
$SectionName = ".mgvl"
$SectionCharacteristics = 1610612768 # 0x60000020: code, execute, read
$PatchVirtualSize = 0xBA
$PatchRawSize = 0x200
$IconPayloadOffset = 0x80

[byte[]]$OriginalGateBytes = @(0x0F, 0x85, 0xB6, 0x04, 0x00, 0x00)
[byte[]]$PatchedGateBytes = @(0x0F, 0x85, 0xCA, 0x00, 0x00, 0x00)
[byte[]]$OriginalIconDispatchBytes = @(0x6A, 0x01, 0x8D, 0x8C, 0x24, 0xC4, 0x00, 0x00, 0x00)
[byte[]]$LegacyIconDispatchBytes = @(0xE9, 0x80, 0xCB, 0x29, 0x00, 0x90, 0x90, 0x90, 0x90)
[byte[]]$LegacyIconPayload = @(
    0x57, 0xE8, 0x6D, 0x35, 0xDD, 0xFF, 0x83, 0xC4, 0x04, 0x83, 0xF8, 0x01, 0x74, 0x1E,
    0x83, 0xF8, 0x02, 0x74, 0x19, 0x8B, 0x47, 0x28, 0x50, 0x8D, 0x84, 0x24, 0xC4, 0x00,
    0x00, 0x00, 0x50, 0xE8, 0xDF, 0x60, 0xD8, 0xFF, 0x83, 0xC4, 0x08, 0xE9, 0xB4, 0x34,
    0xD6, 0xFF, 0x6A, 0x01, 0x8D, 0x8C, 0x24, 0xC4, 0x00, 0x00, 0x00, 0xE9, 0x4A, 0x34,
    0xD6, 0xFF
)
$LegacyIconCodeCaveOffset = 0x33439D

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
    return [uint32](([uint64][Math]::Ceiling([double]$Value / [double]$Alignment)) * $Alignment)
}

function Test-BytesEqual {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected)
    if ($Offset -lt 0 -or ($Offset + $Expected.Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Expected[$i]) { return $false }
    }
    return $true
}

function Test-ZeroRange {
    param([byte[]]$Bytes, [int]$Offset, [int]$Length)
    if ($Offset -lt 0 -or ($Offset + $Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Length; $i++) {
        if ($Bytes[$Offset + $i] -ne 0) { return $false }
    }
    return $true
}

function Write-Bytes {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Patch)
    if ($null -eq $Patch -or $Patch.Length -eq 0) { throw "Refusing to write an empty patch at 0x$($Offset.ToString('X'))." }
    if ($Offset -lt 0 -or ($Offset + $Patch.Length) -gt $Bytes.Length) { throw "Patch range at 0x$($Offset.ToString('X')) is outside MajestyHD.exe." }
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
            Index = $i
            HeaderOffset = $off
            Name = [Text.Encoding]::ASCII.GetString($Bytes[$off..($off + 7)]).TrimEnd([char]0)
            VirtualSize = Read-U32 $Bytes ($off + 8)
            Rva = Read-U32 $Bytes ($off + 12)
            RawSize = Read-U32 $Bytes ($off + 16)
            RawOffset = Read-U32 $Bytes ($off + 20)
            Characteristics = Read-U32 $Bytes ($off + 36)
        }
    }
    return [pscustomobject]@{
        SectionCountOffset = $sectionCountOffset
        SectionCount = $sectionCount
        ImageBase = Read-U32 $Bytes ($optionalHeaderOffset + 28)
        SectionAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 32)
        FileAlignment = Read-U32 $Bytes ($optionalHeaderOffset + 36)
        SizeOfImageOffset = $optionalHeaderOffset + 56
        SizeOfHeaders = Read-U32 $Bytes ($optionalHeaderOffset + 60)
        SectionTableOffset = $sectionTableOffset
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
    $searched = New-Object System.Collections.Generic.List[string]
    $searched.Add($DefaultGamePath)
    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam", "HKCU:\SOFTWARE\Valve\Steam")) {
        try { $path = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath; if ($path) { $steamRoots.Add($path) } } catch {}
    }
    $libraryRoots = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in $steamRoots) {
        $libraryRoots.Add($steamRoot)
        $libraryFile = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libraryFile) {
            foreach ($line in Get-Content -LiteralPath $libraryFile) {
                if ($line -match '"path"\s+"([^"]+)"') { $libraryRoots.Add(($Matches[1] -replace '\\\\', '\')) }
            }
        }
    }
    foreach ($libraryRoot in ($libraryRoots | Select-Object -Unique)) {
        $candidate = Join-Path $libraryRoot "steamapps\common\Majesty HD"
        $searched.Add($candidate)
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $manifest = Join-Path $libraryRoot ("steamapps\appmanifest_" + $appId + ".acf")
        if (Test-Path -LiteralPath $manifest) {
            foreach ($line in Get-Content -LiteralPath $manifest) {
                if ($line -match '"installdir"\s+"([^"]+)"') {
                    $named = Join-Path $libraryRoot ("steamapps\common\" + ($Matches[1] -replace '\\\\', '\'))
                    $searched.Add($named)
                    if (Test-Path -LiteralPath $named) { return $named }
                }
            }
        }
    }
    $lines = ($searched | Select-Object -Unique | ForEach-Object { "  $_" }) -join [Environment]::NewLine
    throw "Could not find Majesty Gold HD.`nLooked in:`n$lines`nRe-run with -GamePath."
}

function Assert-FileWritable {
    param([string]$Path)
    $stream = $null
    try { $stream = [IO.File]::Open($Path, 'Open', 'ReadWrite', 'None') }
    catch { throw "Cannot modify MajestyHD.exe. Close Majesty and try again. If needed, run the BAT as administrator." }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Save-PreInstallBackup {
    param([string]$SourcePath, [string]$BackupDir, [string]$BackupPath)
    if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
    if (Test-Path -LiteralPath $BackupPath) { return }
    Copy-Item -LiteralPath $SourcePath -Destination $BackupPath
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $note = @"
MajestyHD.exe.before-generic-visitor-lists

A copy of MajestyHD.exe taken immediately before Generic Visitor Lists was
first installed, on $stamp.

This is NOT guaranteed to be an unmodified executable. It may already include
other patches. The uninstaller never reads this file; it reverses only this
utility's own guarded changes. Use Steam file verification for a guaranteed
stock executable.
"@
    Set-Content -LiteralPath (Join-Path $BackupDir "READ ME - what this file is.txt") -Value $note -Encoding ASCII
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
if (-not (Test-Path -LiteralPath $exePath)) { throw "Could not find MajestyHD.exe at $exePath." }

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$buildProfile = Get-MajestyBuildProfile $bytes
if ($buildProfile.Key -eq "public") {
    $GateOffset = 0x979D5
    $IconDispatchOffset = 0x97818
    $IconDispatchVa = 0x498418
    $ThreatDispatchOffset = 0x97AD1
    $ThreatDispatchVa = 0x4986D1
    $MonsterResolverOffset = 0xBA4A0
    $MonsterResolverVa = 0x4BB0A0
    $DisplayClassifierOffset = 0x107910
    $DisplayClassifierVa = 0x508510
    $AttributeGetterOffset = 0x1B93D0
    $AttributeGetterVa = 0x5B9FD0
    $IconHeroResumeVa = 0x498421
    $IconMonsterResumeVa = 0x49847D
    [byte[]]$OriginalThreatDispatchBytes = @(0xE8, 0xFA, 0x18, 0x12, 0x00)
    [byte[]]$MonsterResolverSignature = @(
        0x53, 0x55, 0x56, 0x8B, 0x74, 0x24, 0x10, 0x57,
        0x6A, 0x01, 0x8B, 0xCE, 0xE8, 0x8F, 0x72, 0x1B,
        0x00, 0x68, 0x49, 0x58, 0x39, 0x32
    )
    [byte[]]$DisplayClassifierSignature = @(
        0x6A, 0xFF, 0x68, 0x34, 0x07, 0x70, 0x00, 0x64,
        0xA1, 0x00, 0x00, 0x00, 0x00, 0x50, 0x83, 0xEC
    )
    [byte[]]$AttributeGetterSignature = @(
        0x8B, 0x54, 0x24, 0x04, 0x8D, 0x44, 0x24, 0x04,
        0x50, 0x52, 0x83, 0xC1, 0x04, 0xE8, 0x9E, 0x98
    )
    $supportsLegacyPatch = $true
} else {
    $GateOffset = 0x98005
    $IconDispatchOffset = 0x97E48
    $IconDispatchVa = 0x498A48
    $ThreatDispatchOffset = 0x98101
    $ThreatDispatchVa = 0x498D01
    $MonsterResolverOffset = 0xBAEE0
    $MonsterResolverVa = 0x4BBAE0
    $DisplayClassifierOffset = 0x109AE0
    $DisplayClassifierVa = 0x50A6E0
    $AttributeGetterOffset = 0x1CE370
    $AttributeGetterVa = 0x5CEF70
    $IconHeroResumeVa = 0x498A51
    $IconMonsterResumeVa = 0x498AAD
    [byte[]]$OriginalThreatDispatchBytes = @(0xE8, 0x6A, 0x62, 0x13, 0x00)
    [byte[]]$MonsterResolverSignature = @(
        0x53, 0x55, 0x56, 0x8B, 0x74, 0x24, 0x10, 0x57,
        0x6A, 0x01, 0x8B, 0xCE, 0xE8, 0xAF, 0xBC, 0x1C,
        0x00, 0x68, 0x49, 0x58, 0x39, 0x32
    )
    [byte[]]$DisplayClassifierSignature = @(
        0x6A, 0xFF, 0x68, 0x64, 0x61, 0x71, 0x00, 0x64,
        0xA1, 0x00, 0x00, 0x00, 0x00, 0x50, 0x83, 0xEC
    )
    [byte[]]$AttributeGetterSignature = @(
        0x8B, 0x54, 0x24, 0x04, 0x8D, 0x44, 0x24, 0x04,
        0x50, 0x52, 0x83, 0xC1, 0x04, 0xE8, 0x5E, 0x9D
    )
    $supportsLegacyPatch = $false
}
$pe = Get-PeInfo $bytes
$existingSection = $pe.Sections | Where-Object Name -eq $SectionName | Select-Object -First 1

if ($existingSection) {
    $patchRva = [uint32]$existingSection.Rva
    $patchRawOffset = [uint32]$existingSection.RawOffset
    $patchHeaderOffset = [int]$existingSection.HeaderOffset
} else {
    $lastSection = $pe.Sections | Sort-Object RawOffset | Select-Object -Last 1
    $patchRawOffset = Align-Value ([uint32]$bytes.Length) ([uint32]$pe.FileAlignment)
    $lastVirtualEnd = [uint32]($lastSection.Rva + [Math]::Max($lastSection.VirtualSize, $lastSection.RawSize))
    $patchRva = Align-Value $lastVirtualEnd ([uint32]$pe.SectionAlignment)
    $patchHeaderOffset = [int]($pe.SectionTableOffset + ($pe.SectionCount * 40))
    if (($patchHeaderOffset + 40) -gt $pe.SizeOfHeaders) { throw "No room remains in the PE header for the .mgvl patch section." }
    if (-not (Test-ZeroRange $bytes $patchHeaderOffset 40)) { throw "The next PE section-header slot is not empty." }
    if ($patchRawOffset -ne $bytes.Length) { throw "MajestyHD.exe has unaligned trailing data; refusing to append .mgvl." }
}

$patchVa = [uint32]($pe.ImageBase + $patchRva)
$patchHeader = New-SectionHeader $SectionName $PatchVirtualSize $patchRva $PatchRawSize $patchRawOffset
$legacyPatchHeader = New-SectionHeader $SectionName 0x64 $patchRva $PatchRawSize $patchRawOffset
$patchBlob = New-PatchBlob $patchVa
$legacyPatchBlob = New-LegacyPatchBlob $patchVa
$patchedIconDispatch = New-IconDispatchPatch ([uint32]($patchVa + $IconPayloadOffset))
$patchedThreatDispatch = New-RelativeInstruction 0xE8 $ThreatDispatchVa $patchVa
$patchedFileSize = [int]($patchRawOffset + $PatchRawSize)
$newSizeOfImage = Align-Value ([uint32]($patchRva + $PatchVirtualSize)) ([uint32]$pe.SectionAlignment)

$isGateStock = Test-BytesEqual $bytes $GateOffset $OriginalGateBytes
$isGatePatched = Test-BytesEqual $bytes $GateOffset $PatchedGateBytes
$isIconStock = Test-BytesEqual $bytes $IconDispatchOffset $OriginalIconDispatchBytes
$isIconPatched = Test-BytesEqual $bytes $IconDispatchOffset $patchedIconDispatch
$isLegacyIconPatched = $supportsLegacyPatch -and (Test-BytesEqual $bytes $IconDispatchOffset $LegacyIconDispatchBytes) -and
    (Test-BytesEqual $bytes $LegacyIconCodeCaveOffset $LegacyIconPayload)
$isThreatStock = Test-BytesEqual $bytes $ThreatDispatchOffset $OriginalThreatDispatchBytes
$isThreatPatched = Test-BytesEqual $bytes $ThreatDispatchOffset $patchedThreatDispatch
$headerPatched = [bool]$existingSection -and (Test-BytesEqual $bytes $patchHeaderOffset $patchHeader)
$legacyHeaderPatched = $supportsLegacyPatch -and [bool]$existingSection -and (Test-BytesEqual $bytes $patchHeaderOffset $legacyPatchHeader)
$blobPatched = [bool]$existingSection -and (Test-BytesEqual $bytes $patchRawOffset $patchBlob)
$legacyBlobPatched = $supportsLegacyPatch -and [bool]$existingSection -and (Test-BytesEqual $bytes $patchRawOffset $legacyPatchBlob)
$blobEmpty = [bool]$existingSection -and (Test-ZeroRange $bytes $patchRawOffset $PatchRawSize)

if (-not $isGateStock -and -not $isGatePatched) { throw "Unexpected visitor-row category-gate bytes at 0x$($GateOffset.ToString('X'))." }
if (-not $isIconStock -and -not $isIconPatched -and -not $isLegacyIconPatched) { throw "Unexpected visitor-row icon bytes at 0x$($IconDispatchOffset.ToString('X'))." }
if (-not $isThreatStock -and -not $isThreatPatched) { throw "Unexpected visitor-row level-lookup bytes at 0x$($ThreatDispatchOffset.ToString('X'))." }
if ($existingSection -and -not $headerPatched -and -not $legacyHeaderPatched) { throw "The existing .mgvl section header is not owned by this utility." }
if ($existingSection -and -not $blobPatched -and -not $legacyBlobPatched -and -not $blobEmpty) { throw "The existing .mgvl section data is neither installed nor inert." }
if ($isThreatPatched -and -not $blobPatched -and -not $legacyBlobPatched) { throw "The Threat Rank hook points to an incomplete .mgvl section." }
if ($isLegacyIconPatched -and -not ($legacyHeaderPatched -and $legacyBlobPatched -and $isThreatPatched)) { throw "The legacy visitor icon hook is incomplete." }
if (-not (Test-BytesEqual $bytes $MonsterResolverOffset $MonsterResolverSignature)) { throw "The stock IX92/IX94 resolver signature was not found." }
if (-not (Test-BytesEqual $bytes $DisplayClassifierOffset $DisplayClassifierSignature)) { throw "The stock display-category classifier signature was not found." }
if (-not (Test-BytesEqual $bytes $AttributeGetterOffset $AttributeGetterSignature)) { throw "The stock attribute getter signature was not found." }

Write-Host "Majesty Gold HD Generic Visitor Lists installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Game build: $($buildProfile.Name)"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($isGatePatched -and $isIconPatched -and $isThreatPatched -and $headerPatched -and $blobPatched) {
    Write-Host "MajestyHD.exe: generic visitor-list rendering, monster icons, and Threat Ranks are already installed."
    return
}
if ($DryRun) {
    if (-not $existingSection) { Write-Host ("MajestyHD.exe: would append .mgvl at file offset 0x{0:X}." -f $patchRawOffset) }
    elseif (-not $blobPatched) { Write-Host ("MajestyHD.exe: would reactivate .mgvl at file offset 0x{0:X}." -f $patchRawOffset) }
    if ($isGateStock) { Write-Host ("MajestyHD.exe: would redirect the visitor-row category gate at 0x{0:X}." -f $GateOffset) }
    if ($isIconStock) { Write-Host ("MajestyHD.exe: would connect monster rows to the stock icon resolver at 0x{0:X}." -f $IconDispatchOffset) }
    if ($isThreatStock) { Write-Host ("MajestyHD.exe: would enable stock-XP-derived Threat Ranks at 0x{0:X}." -f $ThreatDispatchOffset) }
    return
}

Assert-FileWritable $exePath
$backupDir = Join-Path $resolvedGamePath $BackupDirName
Save-PreInstallBackup $exePath $backupDir (Join-Path $backupDir "MajestyHD.exe.before-generic-visitor-lists")

$targetLength = if ($existingSection) { $bytes.Length } else { $patchedFileSize }
[byte[]]$patchedBytes = New-Object byte[] $targetLength
[Array]::Copy($bytes, 0, $patchedBytes, 0, $bytes.Length)
if (-not $existingSection) {
    [BitConverter]::GetBytes([uint16]($pe.SectionCount + 1)).CopyTo($patchedBytes, $pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$newSizeOfImage).CopyTo($patchedBytes, $pe.SizeOfImageOffset)
}
Write-Bytes $patchedBytes $patchHeaderOffset $patchHeader
Write-Bytes $patchedBytes $GateOffset $PatchedGateBytes
if ($isLegacyIconPatched) { Write-Bytes $patchedBytes $LegacyIconCodeCaveOffset (New-Object byte[] $LegacyIconPayload.Length) }
Write-Bytes $patchedBytes $IconDispatchOffset $patchedIconDispatch
Write-Bytes $patchedBytes $patchRawOffset $patchBlob
Write-Bytes $patchedBytes $ThreatDispatchOffset $patchedThreatDispatch
[IO.File]::WriteAllBytes($exePath, $patchedBytes)

Write-Host "Done. Visitor lists can display valid occupants, stock monster icons, and stock-XP-derived Threat Ranks."
Write-Host "Use Uninstall - Restore Stock Visitor Lists.bat to restore stock filtering."
