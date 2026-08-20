param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupRootName = "_custom_quest_button_originals"
$BackupManifestName = "backup-manifest.json"
$ElementSentinel = [uint32]::MaxValue

# This utility makes exactly two 4-byte edits to MajestyHD.exe. They are undone
# by writing the stock values back, never by restoring a whole-file backup.
#
# Restoring the whole executable would revert every other patch installed since,
# silently: Quest Map Drag, Remember Active Mods, Remember Game Speed, Remember
# Camera Zoom and the Speedrun Timer all write to the same file. Inside the QoL
# bundle that damage was hidden because this uninstaller runs late, after the
# others are already removed. Run standalone, it destroyed all of them.
$CustomQuestObjectBytes = [byte[]](0xC2, 0x0F, 0x00, 0x00)     # stock
$FreestyleObjectBytes = [byte[]](0x88, 0x13, 0x00, 0x00)       # patched

$PublicLegacyUiDataHashes = @{
    "UIData_1280_1024.dat" = "208CB16D60512A3EDE669E84BE93D742D986EC888762E3ED5616B3A1A4AF2276"
    "UIData_1280_768.dat" = "E34333CABFD2D77AD7852C0ED1C59C5323BDF42507A31DEE3A1DF3A055063C75"
    "UIData_1280_800.dat" = "9DF7544803FE62DD5C565A3506AC2A8BF3A453F76FE97F46BF8569805FAAA4CE"
    "UIData_1280_960.dat" = "F79A3DE69F01F4529FF8DC6DF84CA7D8AE39F5299F78152A131B2C82DFCF60DC"
    "UIData_1360_768.dat" = "A7564890F7A4CB609BB651A7843EB4DDFF1666CBBB528DAE48EA8F16931A4569"
    "UIData_1440_900.dat" = "842FC061AB43B52CF7240B684A7B75D87254237C41254A369AAF7CFABC8AEF89"
    "UIData_1600_1200.dat" = "28C8FF5E57DD14C16EB278E80E5F438D3D043E4CCCEBE53D43524CA6E135F662"
    "UIData_1600_900.dat" = "676326A09100F8FE6F94EDF4D74EB4DEF528FF8CD8C905F3CE4F155D6C340498"
    "UIData_1680_1050.dat" = "7717F12AB6023EDE82BE29B262DC45B1A0095613D2A6DE4CCF1F8270AEF822B9"
    "UIData_1920_1080.dat" = "6DC0D1BDA51F07A12EFFAD6DD1393CFEDFC17DC7CD260B4858CA516490B4CBB5"
    "UIData_1920_1200.dat" = "A5519AA28C1C982CD9AC25B9061957C7FD92FA2E8F7636FCE5EC07BDEA81B829"
}

$BuildProfiles = @(
    [pscustomobject]@{
        Id = "public-1.5.2.24"
        DisplayName = "Default Public Version (1.5.2.24)"
        FileVersion = "1.5.2.24"
        TimeDateStamp = [uint32]0x5897B72F
        MinimumLength = 3933696
        SectionHeaderSha256 = "1C1832EEBAB0168B460E237D41CCDFC7552B7E74CCA4ADF41336BE357E541F5A"
        FreestyleIconCallbackOffset = 0x798B6
        FreestyleCallbackBytes = [byte[]](0x00, 0x93, 0x47, 0x00)
        CustomQuestCallbackBytes = [byte[]](0x00, 0x92, 0x47, 0x00)
        CustomQuestCompareImmediateOffset = 0x7A0FE
        LegacyUiDataHashes = $PublicLegacyUiDataHashes
    },
    [pscustomobject]@{
        Id = "beta2-1.5.2.28"
        DisplayName = "beta2 Steam Multiplayer Support (1.5.2.28)"
        FileVersion = "1.5.2.28"
        TimeDateStamp = [uint32]0x5A8A11D5
        MinimumLength = 4056064
        SectionHeaderSha256 = "0618B6C3CD028E21B21EBE0CCF37BACBFA5A5972503AD83C07CA14D502F12C4A"
        FreestyleIconCallbackOffset = 0x78066
        FreestyleCallbackBytes = [byte[]](0xB0, 0x7A, 0x47, 0x00)
        CustomQuestCallbackBytes = [byte[]](0xB0, 0x79, 0x47, 0x00)
        CustomQuestCompareImmediateOffset = 0x789D9
        LegacyUiDataHashes = @{}
    }
)

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

function Read-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Write-U32 {
    param([byte[]]$Bytes, [int]$Offset, [uint32]$Value)
    [Array]::Copy([BitConverter]::GetBytes($Value), 0, $Bytes, $Offset, 4)
}

function Get-CamEntries {
    param([byte[]]$Bytes)

    [byte[]]$magic = @(0x43,0x59,0x4C,0x42,0x50,0x43,0x20,0x20,0x01,0x00,0x01,0x00)
    if (-not (Test-BytesEqual $Bytes 0 $magic)) {
        throw "Not a Majesty CAM/UIData archive."
    }
    $entries = @()
    $sectionCount = [int](Read-U32 $Bytes 12)
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $directory = 20 + ($sectionIndex * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $directory, 4).TrimEnd()
        $sectionHeader = [int](Read-U32 $Bytes ($directory + 4))
        $entryCount = [int](Read-U32 $Bytes $sectionHeader)
        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $entryHeader = $sectionHeader + 8 + ($entryIndex * 28)
            $entries += [pscustomobject]@{
                Extension = $extension
                Name = [Text.Encoding]::ASCII.GetString($Bytes, $entryHeader, 20).TrimEnd([char]0)
                DataOffset = [int](Read-U32 $Bytes ($entryHeader + 20))
                DataSize = [int](Read-U32 $Bytes ($entryHeader + 24))
                DataOffsetField = $entryHeader + 20
                DataSizeField = $entryHeader + 24
            }
        }
    }
    return $entries
}

function Get-NextElementOffset {
    param([byte[]]$Bytes, [int]$EntryOffset, [int]$EntryEnd, [int]$RelativeStart)

    for ($relative = $RelativeStart + 4; $relative -le ($EntryEnd - $EntryOffset - 12); $relative += 4) {
        $absolute = $EntryOffset + $relative
        if (
            (Read-U32 $Bytes $absolute) -eq $ElementSentinel -and
            (Read-U32 $Bytes ($absolute + 4)) -eq 0 -and
            (Read-U32 $Bytes ($absolute + 8)) -eq 2
        ) {
            return $absolute
        }
    }
    return $EntryEnd
}

function Test-ElementHasTokenPair {
    param([byte[]]$Bytes, [int]$Start, [int]$End, [uint32]$Token, [uint32]$Value)
    for ($offset = $Start; $offset -le ($End - 8); $offset += 4) {
        if ((Read-U32 $Bytes $offset) -eq $Token -and (Read-U32 $Bytes ($offset + 4)) -eq $Value) {
            return $true
        }
    }
    return $false
}

function Find-Element {
    param([byte[]]$Bytes, [object]$Entry, [uint32]$TextId, [uint32]$ImageId, [switch]$RequireFixed)

    $entryEnd = $Entry.DataOffset + $Entry.DataSize
    for ($relative = 0; $relative -le ($Entry.DataSize - 28); $relative += 4) {
        $absolute = $Entry.DataOffset + $relative
        if (
            (Read-U32 $Bytes $absolute) -ne $ElementSentinel -or
            (Read-U32 $Bytes ($absolute + 4)) -ne 0 -or
            (Read-U32 $Bytes ($absolute + 8)) -ne 2
        ) { continue }
        $next = Get-NextElementOffset $Bytes $Entry.DataOffset $entryEnd $relative
        $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 33 $TextId
        if (-not $hasText) { $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 7 $TextId }
        $hasImage = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 6 $ImageId
        $hasFixed = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 43 1
        if ($hasText -and $hasImage -and ((-not $RequireFixed) -or $hasFixed)) {
            return [pscustomobject]@{ Offset = $absolute; EndOffset = $next }
        }
    }
    return $null
}

function Get-TokenValueOffsets {
    param([byte[]]$Bytes, [object]$Element, [uint32]$Token)
    $offsets = @()
    for ($offset = $Element.Offset + 28; $offset -le ($Element.EndOffset - 8); $offset += 4) {
        if ((Read-U32 $Bytes $offset) -eq $Token) { $offsets += ($offset + 4) }
    }
    return $offsets
}

function Insert-Bytes {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Inserted)
    [byte[]]$result = New-Object byte[] ($Bytes.Length + $Inserted.Length)
    [Array]::Copy($Bytes, 0, $result, 0, $Offset)
    [Array]::Copy($Inserted, 0, $result, $Offset, $Inserted.Length)
    [Array]::Copy($Bytes, $Offset, $result, $Offset + $Inserted.Length, $Bytes.Length - $Offset)
    return $result
}

function Restore-UiDataOwnedFields {
    param([string]$Path, [string]$BackupPath, [switch]$InspectOnly)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cannot surgically restore missing UIData target $Path."
    }
    [byte[]]$current = [IO.File]::ReadAllBytes($Path)
    [byte[]]$backup = [IO.File]::ReadAllBytes($BackupPath)
    $currentEntries = Get-CamEntries $current
    $backupEntries = Get-CamEntries $backup
    $currentApdb = $currentEntries | Where-Object { $_.Extension -eq "SMNU" -and $_.Name -eq "APdb" } | Select-Object -First 1
    $backupApdb = $backupEntries | Where-Object { $_.Extension -eq "SMNU" -and $_.Name -eq "APdb" } | Select-Object -First 1
    if ($null -eq $currentApdb -or $null -eq $backupApdb) {
        throw "Could not find the APdb quest menu needed for surgical restore in $(Split-Path -Leaf $Path)."
    }

    $backupFreestyle = Find-Element $backup $backupApdb 77 5000 -RequireFixed
    if ($null -eq $backupFreestyle) { $backupFreestyle = Find-Element $backup $backupApdb 17 5000 -RequireFixed }
    $backupMapButton = Find-Element $backup $backupApdb 17 4034
    $currentFreestyle = Find-Element $current $currentApdb 77 5000 -RequireFixed
    if ($null -eq $currentFreestyle) { $currentFreestyle = Find-Element $current $currentApdb 17 5000 -RequireFixed }
    $currentMapButton = Find-Element $current $currentApdb 17 4034
    if ($null -eq $backupFreestyle -or $null -eq $backupMapButton -or $null -eq $currentFreestyle) {
        throw "UIData backup/current APdb records do not match the stock Downloadable Quests lifecycle in $(Split-Path -Leaf $Path)."
    }

    $mapLength = $backupMapButton.EndOffset - $backupMapButton.Offset
    $relativeMapOffset = $backupMapButton.Offset - $backupApdb.DataOffset
    $relativeFreestyleOffset = $backupFreestyle.Offset - $backupApdb.DataOffset
    if ($null -eq $currentMapButton) {
        $expectedCurrentSize = $backupApdb.DataSize - $mapLength
        $insertOffset = $currentApdb.DataOffset + $relativeMapOffset
        if (
            $currentApdb.DataSize -ne $expectedCurrentSize -or
            ($currentFreestyle.Offset - $currentApdb.DataOffset) -ne ($relativeFreestyleOffset - $mapLength)
        ) {
            throw "Current APdb is not exactly the verified backup with this utility's one map-button record removed. Refusing an unsafe insertion in $(Split-Path -Leaf $Path)."
        }

        # The removed record must be bracketed by the same bytes and the same
        # next-element header as the backup. This keeps the insertion on a
        # proven element boundary while allowing Unlock All's independent STRT
        # entry to change length and shift APdb's absolute file offset.
        $prefixLength = [Math]::Min(12, $relativeMapOffset)
        $suffixLength = [Math]::Min(12, ($backupApdb.DataOffset + $backupApdb.DataSize) - $backupMapButton.EndOffset)
        [byte[]]$prefix = New-Object byte[] $prefixLength
        [byte[]]$suffix = New-Object byte[] $suffixLength
        [Array]::Copy($backup, $backupMapButton.Offset - $prefixLength, $prefix, 0, $prefixLength)
        [Array]::Copy($backup, $backupMapButton.EndOffset, $suffix, 0, $suffixLength)
        if (
            -not (Test-BytesEqual $current ($insertOffset - $prefixLength) $prefix) -or
            -not (Test-BytesEqual $current $insertOffset $suffix)
        ) {
            throw "Current APdb bytes do not match the verified map-button removal boundary in $(Split-Path -Leaf $Path)."
        }
    } else {
        $currentRelativeMapOffset = $currentMapButton.Offset - $currentApdb.DataOffset
        if (
            $currentApdb.DataSize -ne $backupApdb.DataSize -or
            $currentRelativeMapOffset -ne $relativeMapOffset -or
            ($currentMapButton.EndOffset - $currentMapButton.Offset) -ne $mapLength -or
            ($currentFreestyle.Offset - $currentApdb.DataOffset) -ne $relativeFreestyleOffset
        ) {
            throw "Current APdb map-button structure differs from its verified backup in $(Split-Path -Leaf $Path)."
        }
    }

    $needsRestore = $null -eq $currentMapButton
    foreach ($fieldOffset in @(12,16,20,24)) {
        if ((Read-U32 $current ($currentFreestyle.Offset + $fieldOffset)) -ne (Read-U32 $backup ($backupFreestyle.Offset + $fieldOffset))) {
            $needsRestore = $true
        }
    }
    foreach ($token in @([uint32]33, [uint32]12, [uint32]13)) {
        $currentOffsets = @(Get-TokenValueOffsets $current $currentFreestyle $token)
        $backupOffsets = @(Get-TokenValueOffsets $backup $backupFreestyle $token)
        if ($currentOffsets.Count -ne $backupOffsets.Count) {
            throw "UIData Freestyle element token layout differs from its verified backup in $(Split-Path -Leaf $Path)."
        }
        for ($i = 0; $i -lt $currentOffsets.Count; $i++) {
            if ((Read-U32 $current $currentOffsets[$i]) -ne (Read-U32 $backup $backupOffsets[$i])) { $needsRestore = $true }
        }
    }
    if (-not $needsRestore) {
        return [pscustomobject]@{ Status = "AlreadyRestored"; Path = $Path }
    }
    if ($InspectOnly) {
        return [pscustomobject]@{ Status = "WouldRestore"; Path = $Path }
    }

    foreach ($fieldOffset in @(12,16,20,24)) {
        Write-U32 $current ($currentFreestyle.Offset + $fieldOffset) (Read-U32 $backup ($backupFreestyle.Offset + $fieldOffset))
    }
    foreach ($token in @([uint32]33, [uint32]12, [uint32]13)) {
        $currentOffsets = @(Get-TokenValueOffsets $current $currentFreestyle $token)
        $backupOffsets = @(Get-TokenValueOffsets $backup $backupFreestyle $token)
        for ($i = 0; $i -lt $currentOffsets.Count; $i++) {
            Write-U32 $current $currentOffsets[$i] (Read-U32 $backup $backupOffsets[$i])
        }
    }

    [byte[]]$newBytes = $current
    if ($null -eq $currentMapButton) {
        [byte[]]$mapBytes = New-Object byte[] $mapLength
        [Array]::Copy($backup, $backupMapButton.Offset, $mapBytes, 0, $mapLength)
        $insertOffset = $currentApdb.DataOffset + $relativeMapOffset
        if ($insertOffset -lt $currentApdb.DataOffset -or $insertOffset -gt ($currentApdb.DataOffset + $currentApdb.DataSize)) {
            throw "Verified map-button insertion point falls outside current APdb in $(Split-Path -Leaf $Path)."
        }
        $newBytes = Insert-Bytes $current $insertOffset $mapBytes
        foreach ($entry in $currentEntries) {
            if ($entry.DataOffset -gt $insertOffset) {
                Write-U32 $newBytes $entry.DataOffsetField ([uint32]($entry.DataOffset + $mapLength))
            }
        }
        Write-U32 $newBytes $currentApdb.DataSizeField ([uint32]($currentApdb.DataSize + $mapLength))
    }
    [IO.File]::WriteAllBytes($Path, $newBytes)
    return [pscustomobject]@{ Status = "Restored"; Path = $Path }
}

function Get-MajestyBuildProfile {
    param([string]$Path, [byte[]]$Bytes)

    if ($Bytes.Length -lt 0x100 -or $Bytes[0] -ne 0x4D -or $Bytes[1] -ne 0x5A) {
        throw "MajestyHD.exe does not have a valid DOS/PE header."
    }
    $peOffset = [BitConverter]::ToInt32($Bytes, 0x3C)
    if ($peOffset -lt 0 -or ($peOffset + 26) -gt $Bytes.Length) {
        throw "MajestyHD.exe has an invalid PE header offset."
    }
    if (
        $Bytes[$peOffset] -ne 0x50 -or $Bytes[$peOffset + 1] -ne 0x45 -or
        $Bytes[$peOffset + 2] -ne 0 -or $Bytes[$peOffset + 3] -ne 0 -or
        [BitConverter]::ToUInt16($Bytes, $peOffset + 4) -ne 0x014C -or
        [BitConverter]::ToUInt16($Bytes, $peOffset + 24) -ne 0x010B
    ) {
        throw "MajestyHD.exe is not the expected 32-bit x86 PE image."
    }

    $timeDateStamp = [BitConverter]::ToUInt32($Bytes, $peOffset + 8)
    $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path).FileVersion
    $profile = @($BuildProfiles | Where-Object {
        $_.FileVersion -eq $fileVersion -and $_.TimeDateStamp -eq $timeDateStamp
    } | Select-Object -First 1)[0]
    if ($null -eq $profile) {
        throw ("Unsupported MajestyHD.exe build. Detected FileVersion '{0}', PE timestamp 0x{1:X8}. Supported builds are the default public 1.5.2.24 release and beta2 1.5.2.28." -f $fileVersion, $timeDateStamp)
    }
    if ($Bytes.Length -lt $profile.MinimumLength) {
        throw ("MajestyHD.exe is shorter than the stock {0} image. Refusing to patch a truncated file." -f $profile.DisplayName)
    }

    $sectionTable = $peOffset + 24 + [BitConverter]::ToUInt16($Bytes, $peOffset + 20)
    if (($sectionTable + 160) -gt $Bytes.Length) { throw "MajestyHD.exe has a truncated section table." }
    [byte[]]$sectionHeaders = New-Object byte[] 160
    [Array]::Copy($Bytes, $sectionTable, $sectionHeaders, 0, 160)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { $sectionHash = ([BitConverter]::ToString($sha256.ComputeHash($sectionHeaders))).Replace('-', '') } finally { $sha256.Dispose() }
    if ($sectionHash -ne $profile.SectionHeaderSha256) {
        throw ("MajestyHD.exe metadata matches {0}, but its four stock section layouts do not. Refusing to guess." -f $profile.DisplayName)
    }

    [byte[]]$callbackPrefix = @(0x8B, 0x50, 0x68, 0x68)
    [byte[]]$callbackSuffix = @(0x33, 0xED, 0x55, 0x6A, 0x07, 0x68, 0x88, 0x13, 0x00, 0x00)
    [byte[]]$comparePrefix = @(0x81, 0xFB)
    [byte[]]$compareSuffix = @(0x74, 0x56, 0x81, 0xFB, 0x88, 0x13, 0x00, 0x00)
    if (
        -not (Test-BytesEqual $Bytes ($profile.FreestyleIconCallbackOffset - 4) $callbackPrefix) -or
        -not (Test-BytesEqual $Bytes ($profile.FreestyleIconCallbackOffset + 4) $callbackSuffix) -or
        -not (Test-BytesEqual $Bytes ($profile.CustomQuestCompareImmediateOffset - 2) $comparePrefix) -or
        -not (Test-BytesEqual $Bytes ($profile.CustomQuestCompareImmediateOffset + 4) $compareSuffix)
    ) {
        throw ("MajestyHD.exe metadata matches {0}, but the stock quest-menu instruction layout does not. Refusing to guess." -f $profile.DisplayName)
    }
    return $profile
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

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Read-BackupManifest {
    param([string]$BackupDir, [object]$BuildProfile)

    $manifestPath = Join-Path $BackupDir $BackupManifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    } catch {
        throw "Backup manifest is unreadable at $manifestPath. Refusing to trust these backups."
    }
    if ($manifest.SchemaVersion -ne 1 -or $manifest.BuildId -ne $BuildProfile.Id) {
        throw ("Backup manifest at {0} belongs to build '{1}', not detected build '{2}'. Refusing a cross-version restore." -f $manifestPath, $manifest.BuildId, $BuildProfile.Id)
    }
    return $manifest
}

function Get-ValidatedBackupRecords {
    param([string]$BackupDir, [object]$Manifest)

    $records = @()
    $seen = @{}
    foreach ($entry in @($Manifest.Files)) {
        $fileName = [string]$entry.Name
        if ($fileName -notmatch '^UIData_[A-Za-z0-9_]+\.dat$' -or $seen.ContainsKey($fileName)) {
            throw "Backup manifest contains an invalid or duplicate UIData filename."
        }
        $seen[$fileName] = $true
        $backupPath = Join-Path $BackupDir ($fileName + ".original")
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            throw "Backup manifest names a missing file: $backupPath"
        }
        $actualHash = Get-FileSha256 $backupPath
        if ($actualHash -ne ([string]$entry.Sha256).ToUpperInvariant()) {
            throw "Backup integrity check failed for $backupPath. Refusing to restore it."
        }
        $records += [pscustomobject]@{ Name = $fileName; SourcePath = $backupPath; Sha256 = $actualHash }
    }
    if ($records.Count -eq 0) {
        throw "Backup manifest contains no UIData backups."
    }
    return $records
}

function Write-BackupManifest {
    param([string]$BackupDir, [object]$BuildProfile, [object[]]$Entries)

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    $manifestPath = Join-Path $BackupDir $BackupManifestName
    $temporaryPath = Join-Path $BackupDir ($BackupManifestName + ".new")
    [ordered]@{
        SchemaVersion = 1
        BuildId = $BuildProfile.Id
        FileVersion = $BuildProfile.FileVersion
        Files = @($Entries | Sort-Object Name)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporaryPath -Encoding ASCII
    Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
}

function Get-CompatibleLegacyBackups {
    param([string]$BackupRoot, [object]$BuildProfile)

    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        return @()
    }
    $records = @()
    foreach ($backup in @(Get-ChildItem -LiteralPath $BackupRoot -Filter "UIData_*.dat.original" -File -ErrorAction SilentlyContinue)) {
        $fileName = $backup.Name -replace '\.original$', ''
        if (
            $BuildProfile.LegacyUiDataHashes.ContainsKey($fileName) -and
            (Get-FileSha256 $backup.FullName) -eq $BuildProfile.LegacyUiDataHashes[$fileName]
        ) {
            $records += [pscustomobject]@{
                Name = $fileName
                SourcePath = $backup.FullName
                Sha256 = (Get-FileSha256 $backup.FullName)
            }
        }
    }
    return $records
}

function Import-LegacyBackups {
    param([object[]]$LegacyRecords, [string]$BackupDir, [object]$BuildProfile)

    if (Test-Path -LiteralPath $BackupDir) {
        $ambiguous = @(Get-ChildItem -LiteralPath $BackupDir -Filter "UIData_*.dat.original" -File -ErrorAction SilentlyContinue)
        if ($ambiguous.Count -gt 0) {
            throw "The build-scoped backup folder $BackupDir has files but no manifest. Refusing to guess their game version."
        }
    } else {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }

    $entries = @()
    foreach ($record in $LegacyRecords) {
        $destination = Join-Path $BackupDir ($record.Name + ".original")
        Copy-Item -LiteralPath $record.SourcePath -Destination $destination
        $entries += [pscustomobject]@{ Name = $record.Name; Sha256 = $record.Sha256 }
    }
    Write-BackupManifest $BackupDir $BuildProfile $entries
    Write-Host ("Imported {0} verified legacy UIData backup(s) into build-scoped folder {1}." -f $LegacyRecords.Count, $BuildProfile.Id)
}

$resolvedGamePath = Get-MajestyPath $GamePath
$dataPath = Join-Path $resolvedGamePath "Data"
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"

if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Could not find MajestyHD.exe at $exePath."
}
[byte[]]$exeBytes = [IO.File]::ReadAllBytes($exePath)
$profile = Get-MajestyBuildProfile $exePath $exeBytes
$backupRoot = Join-Path $dataPath $BackupRootName
$backupDir = Join-Path $backupRoot $profile.Id
$hooks = @(
    @{
        Offset = $profile.FreestyleIconCallbackOffset
        Stock = $profile.FreestyleCallbackBytes
        Patched = $profile.CustomQuestCallbackBytes
        Name = "Freestyle icon hover callback"
    },
    @{
        Offset = $profile.CustomQuestCompareImmediateOffset
        Stock = $CustomQuestObjectBytes
        Patched = $FreestyleObjectBytes
        Name = "Custom Quest click compare"
    }
)

Write-Host "Majesty Gold HD Custom Quest Button restore"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Detected build: $($profile.DisplayName)"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

$manifest = Read-BackupManifest $backupDir $profile
if ($null -ne $manifest) {
    $backupRecords = @(Get-ValidatedBackupRecords $backupDir $manifest)
} else {
    $legacyRecords = @(Get-CompatibleLegacyBackups $backupRoot $profile)
    if ($legacyRecords.Count -eq 0) {
        throw ("No verified UIData backups found for detected build {0}. Legacy backups from another game branch will not be used." -f $profile.DisplayName)
    }
    if ($DryRun) {
        Write-Host ("Would import {0} verified legacy UIData backup(s) for {1}." -f $legacyRecords.Count, $profile.Id)
        $backupRecords = $legacyRecords
    } else {
        Import-LegacyBackups $legacyRecords $backupDir $profile
        $manifest = Read-BackupManifest $backupDir $profile
        $backupRecords = @(Get-ValidatedBackupRecords $backupDir $manifest)
    }
}

# The exe is repaired by reversing our own two edits, so no backup is required.
$exeNeedsRestore = $false
foreach ($hook in $hooks) {
    $isStock = Test-BytesEqual $exeBytes $hook.Offset $hook.Stock
    $isPatched = Test-BytesEqual $exeBytes $hook.Offset $hook.Patched
    if (-not $isStock -and -not $isPatched) {
        $found = [BitConverter]::ToString($exeBytes, $hook.Offset, 4)
        throw ("MajestyHD.exe has unexpected bytes at file offset 0x{0:X} for {1}. Found {2}. Refusing to modify it." -f $hook.Offset, $hook.Name, $found)
    }
    if ($isPatched) {
        $exeNeedsRestore = $true
    }
}

$uiPlans = foreach ($record in $backupRecords) {
    $target = Join-Path $dataPath $record.Name
    Restore-UiDataOwnedFields $target $record.SourcePath -InspectOnly
}

if (-not $DryRun) {
foreach ($plan in @($uiPlans | Where-Object { $_.Status -eq "WouldRestore" })) {
    $target = $plan.Path

    $stream = $null
    try {
        $stream = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        $name = Split-Path -Leaf $target
        throw "Cannot restore $name because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}
}

if ($exeNeedsRestore -and -not $DryRun) {
    $stream = $null
    try {
        $stream = [IO.File]::Open($exePath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot restore MajestyHD.exe because it is in use or not writable. Close Majesty Gold HD and run this restore again. If the game is closed, right-click the BAT and choose Run as administrator."
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

foreach ($record in $backupRecords) {
    $target = Join-Path $dataPath $record.Name
    $plan = @($uiPlans | Where-Object { $_.Path -eq $target } | Select-Object -First 1)[0]
    if ($plan.Status -eq "AlreadyRestored") {
        Write-Host "$($record.Name): already restored"
    } elseif ($DryRun) {
        Write-Host "$($record.Name): would restore"
    } else {
        Restore-UiDataOwnedFields $target $record.SourcePath | Out-Null
        Write-Host "$($record.Name): restored"
    }
}

if ($exeNeedsRestore) {
    if ($DryRun) {
        foreach ($hook in $hooks) {
            if (Test-BytesEqual $exeBytes $hook.Offset $hook.Patched) {
                Write-Host ("MajestyHD.exe: would restore {0} at file offset 0x{1:X}" -f $hook.Name, $hook.Offset)
            }
        }
    } else {
    # Reverse only our own two edits. Never copy a whole backup over the
    # executable: other utilities patch the same file and would be wiped.
    foreach ($hook in $hooks) {
        if (Test-BytesEqual $exeBytes $hook.Offset $hook.Patched) {
            [Array]::Copy($hook.Stock, 0, $exeBytes, $hook.Offset, $hook.Stock.Length)
            Write-Host ("MajestyHD.exe: restored {0} at file offset 0x{1:X}" -f $hook.Name, $hook.Offset)
        }
    }
    [IO.File]::WriteAllBytes($exePath, $exeBytes)
    }
} else {
    Write-Host "MajestyHD.exe: already stock for this utility."
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete."
} else {
    Write-Host "Done. Other utilities that patch MajestyHD.exe were left untouched."
}
