$ErrorActionPreference = "Stop"

$script:DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$script:PatchSectionName = ".mltw"
$script:PatchRawSize = 0x200
$script:PatchVirtualSize = 0x100
$script:PatchSectionCharacteristics = [uint32]1610612768
$script:CustomControlId = [uint32]0x7F01
$script:StockAutoscanControlId = [uint32]0x239E
$script:LowerViewportControlId = [uint32]0x238C
$script:StockAutoscanArtSet = [uint32]0x3F2
$script:TrackArtSet = [uint32]0x3E8
$script:TooltipStubOffset = [uint32]0x80
$script:TooltipStringObjectOffset = [uint32]0xB0
$script:TooltipTextOffset = [uint32]0xC0
$script:TooltipText = "Track selected target in the lower Tracking Window."
$script:CamMagic = [byte[]](0x43, 0x59, 0x4C, 0x42, 0x50, 0x43, 0x20, 0x20, 0x01, 0x00, 0x01, 0x00)

function Read-U16 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Write-U32 {
    param([byte[]]$Bytes, [int]$Offset, [uint32]$Value)
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
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
    if ($null -eq $Patch -or $Patch.Length -eq 0) { throw "Refusing to write an empty patch." }
    if ($Offset -lt 0 -or ($Offset + $Patch.Length) -gt $Bytes.Length) { throw "Patch range is outside the target file." }
    [Array]::Copy($Patch, 0, $Bytes, $Offset, $Patch.Length)
}

function Align-Value {
    param([uint32]$Value, [uint32]$Alignment)
    return [uint32](([uint64]([Math]::Ceiling([double]$Value / [double]$Alignment))) * [uint64]$Alignment)
}

function Get-PeInfo {
    param([byte[]]$Bytes)
    if ($Bytes.Length -lt 0x400 -or (Read-U16 $Bytes 0) -ne 0x5A4D) { throw "MajestyHD.exe is not a valid supported PE image." }
    $peOffset = [int](Read-U32 $Bytes 0x3C)
    if ($peOffset -lt 0 -or ($peOffset + 24) -gt $Bytes.Length -or (Read-U32 $Bytes $peOffset) -ne 0x4550) {
        throw "MajestyHD.exe has an invalid PE header."
    }
    $sectionCountOffset = $peOffset + 6
    $sectionCount = [int](Read-U16 $Bytes $sectionCountOffset)
    $optionalSize = [int](Read-U16 $Bytes ($peOffset + 20))
    $optionalOffset = $peOffset + 24
    $sectionTableOffset = $optionalOffset + $optionalSize
    if ((Read-U16 $Bytes ($peOffset + 4)) -ne 0x014C -or $optionalSize -ne 0xE0 -or (Read-U16 $Bytes $optionalOffset) -ne 0x010B) {
        throw "MajestyHD.exe is not the expected 32-bit x86 image."
    }
    $sizeOfHeaders = [int](Read-U32 $Bytes ($optionalOffset + 60))
    if ($sectionCount -lt 4 -or ($sectionTableOffset + ($sectionCount * 40)) -gt $sizeOfHeaders) {
        throw "MajestyHD.exe has an invalid or truncated section table."
    }
    $sections = @()
    for ($i = 0; $i -lt $sectionCount; $i++) {
        $offset = $sectionTableOffset + ($i * 40)
        $rawSize = [uint32](Read-U32 $Bytes ($offset + 16))
        $rawOffset = [uint32](Read-U32 $Bytes ($offset + 20))
        if ($rawSize -gt 0 -and ($rawOffset -lt $sizeOfHeaders -or ([uint64]$rawOffset + $rawSize) -gt $Bytes.Length)) {
            throw "MajestyHD.exe declares a section outside the file."
        }
        $sections += [pscustomobject]@{
            Index = $i
            HeaderOffset = $offset
            Name = [Text.Encoding]::ASCII.GetString($Bytes[$offset..($offset + 7)]).TrimEnd([char]0)
            VirtualSize = [uint32](Read-U32 $Bytes ($offset + 8))
            Rva = [uint32](Read-U32 $Bytes ($offset + 12))
            RawSize = $rawSize
            RawOffset = $rawOffset
            Characteristics = [uint32](Read-U32 $Bytes ($offset + 36))
        }
    }
    return [pscustomobject]@{
        PeOffset = $peOffset
        Timestamp = [uint32](Read-U32 $Bytes ($peOffset + 8))
        SectionCountOffset = $sectionCountOffset
        SectionCount = $sectionCount
        OptionalOffset = $optionalOffset
        ImageBase = [uint32](Read-U32 $Bytes ($optionalOffset + 28))
        SectionAlignment = [uint32](Read-U32 $Bytes ($optionalOffset + 32))
        FileAlignment = [uint32](Read-U32 $Bytes ($optionalOffset + 36))
        SizeOfImageOffset = $optionalOffset + 56
        SizeOfImage = [uint32](Read-U32 $Bytes ($optionalOffset + 56))
        SizeOfHeaders = $sizeOfHeaders
        SectionTableOffset = $sectionTableOffset
        Sections = $sections
    }
}

function Get-MajestyBuildProfile {
    param([byte[]]$Bytes, [object]$Pe)
    $unsupported = "Unsupported MajestyHD.exe build. This patch supports Steam's Default Public Version (1.5.2.24) and beta2 Steam Multiplayer Support (1.5.2.28)."
    if ($Pe.ImageBase -ne 0x400000 -or $Pe.SectionAlignment -ne 0x1000 -or $Pe.FileAlignment -ne 0x200 -or $Pe.SizeOfHeaders -ne 0x400) {
        throw $unsupported
    }
    if ($Pe.Timestamp -eq 0x5897B72F) {
        $profile = [pscustomobject]@{
            Key = "public"
            DisplayName = "Default Public Version (1.5.2.24)"
            MinimumLength = 0x3C0600
            StockSections = @(
                @(".text", 0x333E7D, 0x001000, 0x334000, 0x000400, 0x60000020),
                @(".rdata", 0x07E88C, 0x335000, 0x07EA00, 0x334400, 0x40000040),
                @(".data", 0x05826C, 0x3B4000, 0x00C800, 0x3B2E00, [uint32]3221225536),
                @(".rsrc", 0x000F34, 0x40D000, 0x001000, 0x3BF600, 0x40000040)
            )
            HandlerOffset = 0x69090
            HandlerVa = [uint32]0x469C90
            OriginalHandlerBytes = [byte[]](0x6A, 0xFF, 0x68, 0xB0, 0xB1, 0x6E, 0x00)
            TooltipHandlerOffset = 0x69A00
            TooltipHandlerVa = [uint32]0x46A600
            OriginalTooltipHandlerBytes = [byte[]](0x83, 0xEC, 0x08, 0x53, 0x55, 0x56, 0x57)
            SetTooltipTextVa = [uint32]0x628350
            GetMainStateVa = [uint32]0x425D00
            PreviousSelectionVa = [uint32]0x467540
            TrackingManagerGlobalVa = [uint32]0x7C12F0
            AssignTargetVa = [uint32]0x454DC0
        }
    } elseif ($Pe.Timestamp -eq 0x5A8A11D5) {
        $profile = [pscustomobject]@{
            Key = "beta2"
            DisplayName = "beta2 Steam Multiplayer Support (1.5.2.28)"
            MinimumLength = 0x3DE400
            StockSections = @(
                @(".text", 0x34C20D, 0x001000, 0x34C400, 0x000400, 0x60000020),
                @(".rdata", 0x08395C, 0x34E000, 0x083A00, 0x34C800, 0x40000040),
                @(".data", 0x058DF4, 0x3D2000, 0x00D200, 0x3D0200, [uint32]3221225536),
                @(".rsrc", 0x000F34, 0x42B000, 0x001000, 0x3DD400, 0x40000040)
            )
            HandlerOffset = 0x6A2D0
            HandlerVa = [uint32]0x46AED0
            OriginalHandlerBytes = [byte[]](0x6A, 0xFF, 0x68, 0xE0, 0x0A, 0x70, 0x00)
            TooltipHandlerOffset = 0x6AC40
            TooltipHandlerVa = [uint32]0x46B840
            OriginalTooltipHandlerBytes = [byte[]](0x83, 0xEC, 0x08, 0x53, 0x55, 0x56, 0x57)
            SetTooltipTextVa = [uint32]0x63AAF0
            GetMainStateVa = [uint32]0x426CD0
            PreviousSelectionVa = [uint32]0x468780
            TrackingManagerGlobalVa = [uint32]0x7DFDA8
            AssignTargetVa = [uint32]0x455DF0
        }
    } else {
        throw $unsupported
    }
    if ($Bytes.Length -lt $profile.MinimumLength) { throw $unsupported }
    for ($i = 0; $i -lt 4; $i++) {
        $actual = $Pe.Sections[$i]
        $expected = $profile.StockSections[$i]
        if ($actual.Name -ne $expected[0] -or $actual.VirtualSize -ne [uint32]$expected[1] -or
            $actual.Rva -ne [uint32]$expected[2] -or $actual.RawSize -ne [uint32]$expected[3] -or
            $actual.RawOffset -ne [uint32]$expected[4] -or $actual.Characteristics -ne [uint32]$expected[5]) {
            throw $unsupported
        }
    }
    return $profile
}

function New-RelativeJumpBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)
    $result = New-Object byte[] 5
    $result[0] = 0xE9
    [BitConverter]::GetBytes([int]([int64]$TargetVa - ([int64]$SourceVa + 5))).CopyTo($result, 1)
    return $result
}

function New-RelativeCallBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)
    $result = New-RelativeJumpBytes $SourceVa $TargetVa
    $result[0] = 0xE8
    return $result
}

function New-SectionHeader {
    param([uint32]$Rva, [uint32]$RawOffset)
    $result = New-Object byte[] 40
    [Text.Encoding]::ASCII.GetBytes($script:PatchSectionName).CopyTo($result, 0)
    Write-U32 $result 8 $script:PatchVirtualSize
    Write-U32 $result 12 $Rva
    Write-U32 $result 16 $script:PatchRawSize
    Write-U32 $result 20 $RawOffset
    Write-U32 $result 36 $script:PatchSectionCharacteristics
    return $result
}

function New-HandlerHook {
    param([object]$Profile, [uint32]$PatchVa)
    [byte[]]$result = New-Object byte[] 7
    (New-RelativeJumpBytes $Profile.HandlerVa $PatchVa).CopyTo($result, 0)
    $result[5] = 0x90
    $result[6] = 0x90
    return $result
}

function New-TooltipHook {
    param([object]$Profile, [uint32]$PatchVa)
    [byte[]]$result = New-Object byte[] 7
    (New-RelativeJumpBytes $Profile.TooltipHandlerVa ([uint32]($PatchVa + $script:TooltipStubOffset))).CopyTo($result, 0)
    $result[5] = 0x90
    $result[6] = 0x90
    return $result
}

function New-NoTooltipPatchBlob {
    param([object]$Profile, [uint32]$PatchVa)
    [byte[]]$result = New-Object byte[] $script:PatchRawSize
    [byte[]]$fixed = @(
        0x81, 0x7C, 0x24, 0x04, 0x01, 0x7F, 0x00, 0x00,
        0x0F, 0x85, 0x1F, 0x00, 0x00, 0x00,
        0xE8, 0, 0, 0, 0,
        0x8B, 0x40, 0x48,
        0x85, 0xC0,
        0x74, 0x0E,
        0x6A, 0x02,
        0x8B, 0x0D, 0, 0, 0, 0,
        0x50,
        0xE8, 0, 0, 0, 0,
        0x33, 0xC0,
        0xC2, 0x04, 0x00
    )
    $fixed.CopyTo($result, 0)
    (New-RelativeCallBytes ($PatchVa + 14) $Profile.GetMainStateVa)[1..4].CopyTo($result, 15)
    Write-U32 $result 30 $Profile.TrackingManagerGlobalVa
    (New-RelativeCallBytes ($PatchVa + 35) $Profile.AssignTargetVa)[1..4].CopyTo($result, 36)
    $Profile.OriginalHandlerBytes.CopyTo($result, 45)
    (New-RelativeJumpBytes ($PatchVa + 52) ($Profile.HandlerVa + 7)).CopyTo($result, 52)
    return $result
}

function New-PatchBlob {
    param([object]$Profile, [uint32]$PatchVa)
    [byte[]]$result = New-NoTooltipPatchBlob $Profile $PatchVa
    $stubOffset = [int]$script:TooltipStubOffset
    $stubVa = [uint32]($PatchVa + $script:TooltipStubOffset)
    [byte[]]$fixed = @(
        0x81, 0x7C, 0x24, 0x04, 0x01, 0x7F, 0x00, 0x00,
        0x0F, 0x85, 0x13, 0x00, 0x00, 0x00,
        0x8B, 0x4C, 0x24, 0x0C,
        0x68, 0, 0, 0, 0,
        0xE8, 0, 0, 0, 0,
        0xB0, 0x01,
        0xC2, 0x0C, 0x00
    )
    $fixed.CopyTo($result, $stubOffset)
    Write-U32 $result ($stubOffset + 19) ([uint32]($PatchVa + $script:TooltipStringObjectOffset))
    (New-RelativeCallBytes ([uint32]($stubVa + 23)) $Profile.SetTooltipTextVa)[1..4].CopyTo($result, ($stubOffset + 24))
    $Profile.OriginalTooltipHandlerBytes.CopyTo($result, ($stubOffset + 33))
    (New-RelativeJumpBytes ([uint32]($stubVa + 40)) ([uint32]($Profile.TooltipHandlerVa + 7))).CopyTo($result, ($stubOffset + 40))
    [byte[]]$textBytes = [Text.Encoding]::ASCII.GetBytes($script:TooltipText + [char]0)
    if (($script:TooltipTextOffset + $textBytes.Length) -gt $script:PatchVirtualSize) { throw "The tooltip text exceeds the .mltw virtual section." }
    $textLength = [uint32]($textBytes.Length - 1)
    Write-U32 $result ([int]$script:TooltipStringObjectOffset) ([uint32]($PatchVa + $script:TooltipTextOffset))
    Write-U32 $result ([int]($script:TooltipStringObjectOffset + 4)) $textLength
    Write-U32 $result ([int]($script:TooltipStringObjectOffset + 8)) $textLength
    $textBytes.CopyTo($result, [int]$script:TooltipTextOffset)
    return $result
}

function New-StockAutoscanIdPatchBlob {
    param([object]$Profile, [uint32]$PatchVa)
    # Migration-only signature for the short-lived development build that
    # routed the stock Autoscan ID before the native control was privatized.
    [byte[]]$result = New-NoTooltipPatchBlob $Profile $PatchVa
    Write-U32 $result 4 $script:StockAutoscanControlId
    return $result
}

function New-PreviousPatchBlob {
    param([object]$Profile, [uint32]$PatchVa)
    [byte[]]$result = New-Object byte[] $script:PatchRawSize
    [byte[]]$fixed = @(
        0x81, 0x7C, 0x24, 0x04, 0x01, 0x7F, 0x00, 0x00,
        0x0F, 0x85, 0x1C, 0x00, 0x00, 0x00,
        0xE8, 0, 0, 0, 0,
        0x85, 0xC0,
        0x74, 0x0E,
        0x6A, 0x02,
        0x8B, 0x0D, 0, 0, 0, 0,
        0x50,
        0xE8, 0, 0, 0, 0,
        0x33, 0xC0,
        0xC2, 0x04, 0x00
    )
    $fixed.CopyTo($result, 0)
    (New-RelativeCallBytes ($PatchVa + 14) $Profile.PreviousSelectionVa)[1..4].CopyTo($result, 15)
    Write-U32 $result 27 $Profile.TrackingManagerGlobalVa
    (New-RelativeCallBytes ($PatchVa + 32) $Profile.AssignTargetVa)[1..4].CopyTo($result, 33)
    $Profile.OriginalHandlerBytes.CopyTo($result, 42)
    (New-RelativeJumpBytes ($PatchVa + 49) ($Profile.HandlerVa + 7)).CopyTo($result, 49)
    return $result
}

function Get-MajestyPath {
    param([string]$RequestedPath)
    if ($RequestedPath) { return $RequestedPath }
    if (Test-Path -LiteralPath $script:DefaultGamePath) { return $script:DefaultGamePath }
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam", "HKCU:\SOFTWARE\Valve\Steam")) {
        try {
            $value = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($value) { $roots.Add($value) }
        } catch {}
    }
    foreach ($root in ($roots | Select-Object -Unique)) {
        $libraries = @($root)
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '"path"\s+"([^"]+)"') { $libraries += ($Matches[1] -replace '\\\\', '\') }
            }
        }
        foreach ($library in ($libraries | Select-Object -Unique)) {
            $candidate = Join-Path $library "steamapps\common\Majesty HD"
            if (Test-Path -LiteralPath (Join-Path $candidate "MajestyHD.exe")) { return $candidate }
        }
    }
    throw 'Could not find Majesty Gold HD. Re-run with -GamePath "D:\Path\To\Majesty HD".'
}

function Assert-FileWritable {
    param([string]$Path)
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot modify $(Split-Path -Leaf $Path). Close Majesty and try again; if necessary, run as administrator."
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-CamEntries {
    param([byte[]]$Bytes)
    if (-not (Test-BytesEqual $Bytes 0 $script:CamMagic)) { throw "Not a Majesty CAM/UIData archive." }
    $entries = @()
    $sectionCount = [int](Read-U32 $Bytes 12)
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $directory = 20 + ($sectionIndex * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $directory, 4).TrimEnd()
        $sectionOffset = [int](Read-U32 $Bytes ($directory + 4))
        $entryCount = [int](Read-U32 $Bytes $sectionOffset)
        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $header = $sectionOffset + 8 + ($entryIndex * 28)
            $entries += [pscustomobject]@{
                Extension = $extension
                Name = [Text.Encoding]::ASCII.GetString($Bytes, $header, 20).TrimEnd([char]0)
                DataOffset = [int](Read-U32 $Bytes ($header + 20))
                DataSize = [int](Read-U32 $Bytes ($header + 24))
                DataOffsetField = $header + 20
                DataSizeField = $header + 24
            }
        }
    }
    return $entries
}

function Get-NextElementOffset {
    param([byte[]]$Bytes, [object]$Entry, [int]$Start)
    $end = $Entry.DataOffset + $Entry.DataSize
    for ($offset = $Start + 4; $offset -le ($end - 12); $offset += 4) {
        if ((Read-U32 $Bytes $offset) -eq [uint32]::MaxValue -and (Read-U32 $Bytes ($offset + 4)) -ne [uint32]::MaxValue -and (Read-U32 $Bytes ($offset + 8)) -eq 2) {
            return $offset
        }
    }
    return $end
}

function Find-ElementByControlId {
    param([byte[]]$Bytes, [object]$Entry, [uint32]$ControlId)
    $matches = @()
    $entryEnd = $Entry.DataOffset + $Entry.DataSize
    for ($offset = $Entry.DataOffset; $offset -le ($entryEnd - 28); $offset += 4) {
        if ((Read-U32 $Bytes $offset) -ne [uint32]::MaxValue -or (Read-U32 $Bytes ($offset + 4)) -eq [uint32]::MaxValue -or (Read-U32 $Bytes ($offset + 8)) -ne 2) { continue }
        $next = Get-NextElementOffset $Bytes $Entry $offset
        for ($pair = $offset + 28; $pair -le ($next - 8); $pair += 8) {
            if ((Read-U32 $Bytes $pair) -eq 6 -and (Read-U32 $Bytes ($pair + 4)) -eq $ControlId) {
                $matches += [pscustomobject]@{
                    Offset = $offset
                    EndOffset = $next
                    X = [int](Read-U32 $Bytes ($offset + 12))
                    Y = [int](Read-U32 $Bytes ($offset + 16))
                    Width = [int](Read-U32 $Bytes ($offset + 20))
                    Height = [int](Read-U32 $Bytes ($offset + 24))
                }
                break
            }
        }
    }
    if ($matches.Count -gt 1) { throw ("Found duplicate control ID 0x{0:X} in APMK." -f $ControlId) }
    return @($matches | Select-Object -First 1)[0]
}

function Get-UiInstallPlan {
    param([string]$Path)
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    $entries = @(Get-CamEntries $bytes)
    $apmk = @($entries | Where-Object { $_.Extension -eq "SMNU" -and $_.Name -eq "APMK" } | Select-Object -First 1)[0]
    if ($null -eq $apmk) { return [pscustomobject]@{ Path = $Path; Status = "SkippedNoLowerWindow"; Bytes = $bytes } }
    $lower = Find-ElementByControlId $bytes $apmk $script:LowerViewportControlId
    if ($null -eq $lower) { return [pscustomobject]@{ Path = $Path; Status = "SkippedNoLowerWindow"; Bytes = $bytes } }
    $privateControl = Find-ElementByControlId $bytes $apmk $script:CustomControlId
    $stockControl = Find-ElementByControlId $bytes $apmk $script:StockAutoscanControlId
    if ($null -ne $privateControl -and $null -ne $stockControl) {
        throw "APMK contains both the stock and private lower Autoscan control IDs in $(Split-Path -Leaf $Path)."
    }
    $control = if ($null -ne $privateControl) { $privateControl } else { $stockControl }
    if ($null -eq $control) { throw "APMK is missing the stock/private lower Autoscan control in $(Split-Path -Leaf $Path)." }
    $idValueOffset = -1
    $artValueOffset = -1
    for ($pair = $control.Offset + 28; $pair -le ($control.EndOffset - 8); $pair += 8) {
        $token = Read-U32 $bytes $pair
        if ($token -eq 6) { $idValueOffset = $pair + 4 }
        elseif ($token -eq 13) { $artValueOffset = $pair + 4 }
    }
    if ($idValueOffset -lt 0) { throw "The lower Autoscan control has no control-ID token in $(Split-Path -Leaf $Path)." }
    if ($artValueOffset -lt 0) { throw "The stock lower Autoscan control has no INTG art-set token in $(Split-Path -Leaf $Path)." }
    $currentId = Read-U32 $bytes $idValueOffset
    $currentArt = Read-U32 $bytes $artValueOffset
    if ($currentId -eq $script:CustomControlId -and $currentArt -eq $script:TrackArtSet) {
        return [pscustomobject]@{ Path = $Path; Status = "AlreadyPatched"; Bytes = $bytes }
    }
    if ($currentId -eq $script:StockAutoscanControlId -and $currentArt -eq $script:StockAutoscanArtSet) {
        $status = "WouldPatch"
    } elseif ($currentId -eq $script:StockAutoscanControlId -and $currentArt -eq $script:TrackArtSet) {
        $status = "WouldUpgrade"
    } else {
        throw ("The lower Autoscan control ID/artwork pair is neither stock nor patch-owned in {0}." -f (Split-Path -Leaf $Path))
    }
    [byte[]]$patched = [byte[]]$bytes.Clone()
    Write-U32 $patched $idValueOffset $script:CustomControlId
    Write-U32 $patched $artValueOffset $script:TrackArtSet
    return [pscustomobject]@{ Path = $Path; Status = $status; Bytes = $patched }
}

function Get-UiRestorePlan {
    param([string]$Path)
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    $entries = @(Get-CamEntries $bytes)
    $apmk = @($entries | Where-Object { $_.Extension -eq "SMNU" -and $_.Name -eq "APMK" } | Select-Object -First 1)[0]
    if ($null -eq $apmk) { return [pscustomobject]@{ Path = $Path; Status = "SkippedNoLowerWindow"; Bytes = $bytes } }
    $lower = Find-ElementByControlId $bytes $apmk $script:LowerViewportControlId
    if ($null -eq $lower) { return [pscustomobject]@{ Path = $Path; Status = "SkippedNoLowerWindow"; Bytes = $bytes } }
    $privateControl = Find-ElementByControlId $bytes $apmk $script:CustomControlId
    $stockControl = Find-ElementByControlId $bytes $apmk $script:StockAutoscanControlId
    if ($null -ne $privateControl -and $null -ne $stockControl) {
        throw "APMK contains both the stock and private lower Autoscan control IDs in $(Split-Path -Leaf $Path)."
    }
    $control = if ($null -ne $privateControl) { $privateControl } else { $stockControl }
    if ($null -eq $control) { throw "APMK is missing the stock/private lower Autoscan control in $(Split-Path -Leaf $Path)." }
    $idValueOffset = -1
    $artValueOffset = -1
    for ($pair = $control.Offset + 28; $pair -le ($control.EndOffset - 8); $pair += 8) {
        $token = Read-U32 $bytes $pair
        if ($token -eq 6) { $idValueOffset = $pair + 4 }
        elseif ($token -eq 13) { $artValueOffset = $pair + 4 }
    }
    if ($idValueOffset -lt 0) { throw "The lower Autoscan control has no control-ID token in $(Split-Path -Leaf $Path)." }
    if ($artValueOffset -lt 0) { throw "The lower Autoscan control has no INTG art-set token in $(Split-Path -Leaf $Path)." }
    $currentId = Read-U32 $bytes $idValueOffset
    $currentArt = Read-U32 $bytes $artValueOffset
    if ($currentId -eq $script:StockAutoscanControlId -and $currentArt -eq $script:StockAutoscanArtSet) {
        return [pscustomobject]@{ Path = $Path; Status = "AlreadyStock"; Bytes = $bytes }
    }
    if (-not (($currentId -eq $script:CustomControlId -and $currentArt -eq $script:TrackArtSet) -or
              ($currentId -eq $script:StockAutoscanControlId -and $currentArt -eq $script:TrackArtSet))) {
        throw "The lower Autoscan control ID/artwork pair is corrupt in $(Split-Path -Leaf $Path)."
    }
    [byte[]]$restored = [byte[]]$bytes.Clone()
    Write-U32 $restored $idValueOffset $script:StockAutoscanControlId
    Write-U32 $restored $artValueOffset $script:StockAutoscanArtSet
    return [pscustomobject]@{ Path = $Path; Status = "WouldRestore"; Bytes = $restored }
}

function Write-FileAtomically {
    param([string]$Path, [byte[]]$Bytes)
    $temporary = $Path + ".mltw-new"
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}
