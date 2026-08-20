param(
    [string]$GamePath = "",
    [Nullable[int]]$X = $null,
    [Nullable[int]]$Y = $null,
    [int]$Width = 97,
    [int]$Height = 93,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$Magic = [byte[]](0x43, 0x59, 0x4C, 0x42, 0x50, 0x43, 0x20, 0x20, 0x01, 0x00, 0x01, 0x00)
$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$ElementSentinel = [uint32]::MaxValue
$INPq = [BitConverter]::ToUInt32([Text.Encoding]::ASCII.GetBytes("INPq"), 0)
$IX34 = [BitConverter]::ToUInt32([Text.Encoding]::ASCII.GetBytes("IX34"), 0)
$CustomQuestObjectBytes = [byte[]](0xC2, 0x0F, 0x00, 0x00)
$FreestyleObjectBytes = [byte[]](0x88, 0x13, 0x00, 0x00)
$StockFreestyleFrame = 1039
$BackupRootName = "_custom_quest_button_originals"
$BackupManifestName = "backup-manifest.json"

# Only the default branch could have been installed by versions that used the
# old, unscoped backup folder. These exact stock hashes let us import those old
# backups safely. A public archive is never accepted as a beta2 backup.
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

# Version resources plus the PE linker timestamp identify the Steam branch.
# Target-adjacent instruction bytes below guard the exact stock menu lifecycle
# even when other compatible QOL patches have changed unrelated executable data.
$BuildProfiles = @(
    [pscustomobject]@{
        Id = "public-1.5.2.24"
        DisplayName = "Default Public Version (1.5.2.24)"
        FileVersion = "1.5.2.24"
        TimeDateStamp = [uint32]0x5897B72F
        MinimumLength = 3933696
        SectionHeaderSha256 = "1C1832EEBAB0168B460E237D41CCDFC7552B7E74CCA4ADF41336BE357E541F5A"
        StockSha256 = "AA9BE61DC095773CCC5C08B9E5729A30EE856258249371C5189CE52FB675DB00"
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
        StockSha256 = "99848B5DB16CC3EA540D7E909CB24966AD9F3CD15D302CDE47AAB3BA81E3167E"
        FreestyleIconCallbackOffset = 0x78066
        FreestyleCallbackBytes = [byte[]](0xB0, 0x7A, 0x47, 0x00)
        CustomQuestCallbackBytes = [byte[]](0xB0, 0x79, 0x47, 0x00)
        CustomQuestCompareImmediateOffset = 0x789D9
        LegacyUiDataHashes = @{}
    }
)

function Read-U32 {
    param([byte[]]$Bytes, [int]$Offset)
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Write-U32 {
    param([byte[]]$Bytes, [int]$Offset, [uint32]$Value)
    [byte[]]$Raw = [BitConverter]::GetBytes($Value)
    [Array]::Copy($Raw, 0, $Bytes, $Offset, 4)
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

function Test-Magic {
    param([byte[]]$Bytes)
    if ($Bytes.Length -lt 20) {
        return $false
    }
    for ($i = 0; $i -lt $Magic.Length; $i++) {
        if ($Bytes[$i] -ne $Magic[$i]) {
            return $false
        }
    }
    return $true
}

function Get-CamEntries {
    param([byte[]]$Bytes)

    if (-not (Test-Magic $Bytes)) {
        throw "Not a Majesty CAM/UIData archive."
    }

    $sectionCount = [int](Read-U32 $Bytes 12)
    $entries = @()
    for ($sectionIndex = 0; $sectionIndex -lt $sectionCount; $sectionIndex++) {
        $dir = 20 + ($sectionIndex * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $dir, 4).TrimEnd()
        $sectionHeaderOffset = [int](Read-U32 $Bytes ($dir + 4))
        $entryCount = [int](Read-U32 $Bytes $sectionHeaderOffset)

        for ($entryIndex = 0; $entryIndex -lt $entryCount; $entryIndex++) {
            $entryHeader = $sectionHeaderOffset + 8 + ($entryIndex * 28)
            $name = [Text.Encoding]::ASCII.GetString($Bytes, $entryHeader, 20).TrimEnd([char]0)
            $entries += [pscustomobject]@{
                Extension = $extension
                Name = $name
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
    param(
        [byte[]]$Bytes,
        [int]$Start,
        [int]$End,
        [uint32]$Token,
        [uint32]$Value
    )

    for ($offset = $Start; $offset -le ($End - 8); $offset += 4) {
        if ((Read-U32 $Bytes $offset) -eq $Token -and (Read-U32 $Bytes ($offset + 4)) -eq $Value) {
            return $true
        }
    }
    return $false
}

function Find-Element {
    param(
        [byte[]]$Bytes,
        [object]$Entry,
        [uint32]$TextId,
        [uint32]$ImageId,
        [switch]$RequireFixed
    )

    $entryOffset = $Entry.DataOffset
    $entryEnd = $Entry.DataOffset + $Entry.DataSize
    for ($relative = 0; $relative -le ($Entry.DataSize - 28); $relative += 4) {
        $absolute = $entryOffset + $relative
        if (
            (Read-U32 $Bytes $absolute) -ne $ElementSentinel -or
            (Read-U32 $Bytes ($absolute + 4)) -ne 0 -or
            (Read-U32 $Bytes ($absolute + 8)) -ne 2
        ) {
            continue
        }

        $next = Get-NextElementOffset $Bytes $entryOffset $entryEnd $relative
        $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 33 $TextId
        if (-not $hasText) {
            $hasText = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 7 $TextId
        }
        $hasImage = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 6 $ImageId
        $hasFixed = Test-ElementHasTokenPair $Bytes ($absolute + 28) $next 43 1
        if ($hasText -and $hasImage -and ((-not $RequireFixed) -or $hasFixed)) {
            return [pscustomobject]@{
                Offset = $absolute
                EndOffset = $next
                X = [int](Read-U32 $Bytes ($absolute + 12))
                Y = [int](Read-U32 $Bytes ($absolute + 16))
                Width = [int](Read-U32 $Bytes ($absolute + 20))
                Height = [int](Read-U32 $Bytes ($absolute + 24))
            }
        }
    }
    return $null
}

function Remove-Bytes {
    param([byte[]]$Bytes, [int]$Start, [int]$End)

    $length = $End - $Start
    [byte[]]$result = New-Object byte[] ($Bytes.Length - $length)
    [Array]::Copy($Bytes, 0, $result, 0, $Start)
    [Array]::Copy($Bytes, $End, $result, $Start, $Bytes.Length - $End)
    return $result
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

function Assert-FilesWritable {
    param([object[]]$Files)

    foreach ($file in $Files) {
        Assert-FileWritable $file.FullName
    }
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

function Write-BackupManifest {
    param([string]$BackupDir, [object]$BuildProfile, [object[]]$Entries)

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    $manifestPath = Join-Path $BackupDir $BackupManifestName
    $temporaryPath = Join-Path $BackupDir ($BackupManifestName + ".new")
    $document = [ordered]@{
        SchemaVersion = 1
        BuildId = $BuildProfile.Id
        FileVersion = $BuildProfile.FileVersion
        Files = @($Entries | Sort-Object Name)
    }
    $document | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temporaryPath -Encoding ASCII
    Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
}

function Assert-ManifestBackupsValid {
    param([string]$BackupDir, [object]$Manifest)

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
            throw "Backup integrity check failed for $backupPath. Refusing to overwrite it or use it for restore."
        }
    }
}

function Save-UiDataBackup {
    param([string]$SourcePath, [string]$BackupDir, [object]$BuildProfile)

    $fileName = Split-Path -Leaf $SourcePath
    $backupPath = Join-Path $BackupDir ($fileName + ".original")
    $manifest = Read-BackupManifest $BackupDir $BuildProfile
    $entries = @()
    if ($null -ne $manifest) {
        Assert-ManifestBackupsValid $BackupDir $manifest
        $entries = @($manifest.Files)
    }

    $record = @($entries | Where-Object { $_.Name -eq $fileName } | Select-Object -First 1)[0]
    if ($null -ne $record) {
        return
    }
    if (Test-Path -LiteralPath $backupPath) {
        throw "Found an unmanifested backup at $backupPath. Refusing to overwrite an ambiguous file."
    }
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $backupPath
    $entries += [pscustomobject]@{ Name = $fileName; Sha256 = (Get-FileSha256 $backupPath) }
    Write-BackupManifest $BackupDir $BuildProfile $entries
}

function Import-CompatibleLegacyBackups {
    param([string]$BackupRoot, [string]$BackupDir, [object]$BuildProfile)

    if (Test-Path -LiteralPath (Join-Path $BackupDir $BackupManifestName)) {
        $manifest = Read-BackupManifest $BackupDir $BuildProfile
        Assert-ManifestBackupsValid $BackupDir $manifest
        return
    }
    if (Test-Path -LiteralPath $BackupDir) {
        $ambiguous = @(Get-ChildItem -LiteralPath $BackupDir -Filter "UIData_*.dat.original" -File -ErrorAction SilentlyContinue)
        if ($ambiguous.Count -gt 0) {
            throw "The build-scoped backup folder $BackupDir has files but no manifest. Refusing to guess their game version."
        }
    }
    if (-not (Test-Path -LiteralPath $BackupRoot)) {
        return
    }

    $legacy = @(Get-ChildItem -LiteralPath $BackupRoot -Filter "UIData_*.dat.original" -File -ErrorAction SilentlyContinue)
    if ($legacy.Count -eq 0) {
        return
    }
    $compatible = @()
    foreach ($backup in $legacy) {
        $fileName = $backup.Name -replace '\.original$', ''
        if (
            $BuildProfile.LegacyUiDataHashes.ContainsKey($fileName) -and
            (Get-FileSha256 $backup.FullName) -eq $BuildProfile.LegacyUiDataHashes[$fileName]
        ) {
            $compatible += $backup
        }
    }
    if ($compatible.Count -eq 0) {
        Write-Host ("Legacy UIData backups were ignored because none match detected build {0}." -f $BuildProfile.DisplayName)
        return
    }

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    $entries = @()
    foreach ($backup in $compatible) {
        $destination = Join-Path $BackupDir $backup.Name
        Copy-Item -LiteralPath $backup.FullName -Destination $destination
        $entries += [pscustomobject]@{
            Name = ($backup.Name -replace '\.original$', '')
            Sha256 = (Get-FileSha256 $destination)
        }
    }
    Write-BackupManifest $BackupDir $BuildProfile $entries
    Write-Host ("Imported {0} verified legacy UIData backup(s) into build-scoped folder {1}." -f $compatible.Count, $BuildProfile.Id)
}

function Patch-UiDataFile {
    param([string]$Path, [string]$BackupDir, [object]$BuildProfile)

    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    $entries = Get-CamEntries $bytes
    $apdb = @($entries | Where-Object { $_.Extension -eq "SMNU" -and $_.Name -eq "APdb" } | Select-Object -First 1)[0]
    if ($null -eq $apdb) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "No APdb quest menu in this resolution."; Path = $Path }
    }

    $freestyle = Find-Element $bytes $apdb 77 5000 -RequireFixed
    if ($null -eq $freestyle) {
        $freestyle = Find-Element $bytes $apdb 17 5000 -RequireFixed
    }
    if ($null -eq $freestyle) {
        return [pscustomobject]@{ Status = "Skipped"; Reason = "Could not find the fixed Freestyle icon record."; Path = $Path }
    }

    $freestyleLabel = Find-Element $bytes $apdb 82 5900
    $mapButton = Find-Element $bytes $apdb 17 4034

    if ($null -ne $freestyleLabel) {
        $stockX = $freestyleLabel.X + 40
        $stockY = $freestyleLabel.Y - 59
    } else {
        $stockX = $freestyle.X
        $stockY = $freestyle.Y
    }

    $targetX = if ($X.HasValue) { $X.Value } else { $stockX }
    $targetY = if ($Y.HasValue) { $Y.Value } else { $stockY }

    $needsIconRepair = (
        $freestyle.X -ne $targetX -or
        $freestyle.Y -ne $targetY -or
        $freestyle.Width -ne $Width -or
        $freestyle.Height -ne $Height -or
        (Test-ElementHasTokenPair $bytes ($freestyle.Offset + 28) $freestyle.EndOffset 33 17) -or
        (Test-ElementHasTokenPair $bytes ($freestyle.Offset + 28) $freestyle.EndOffset 12 $IX34)
    )

    for ($offset = $freestyle.Offset + 28; $offset -le ($freestyle.EndOffset - 8); $offset += 4) {
        if ((Read-U32 $bytes $offset) -eq 13 -and (Read-U32 $bytes ($offset + 4)) -ne $StockFreestyleFrame) {
            $needsIconRepair = $true
        }
    }

    $status = if ((-not $needsIconRepair) -and $null -eq $mapButton) { "AlreadyPatched" } else { "Patched" }
    $result = [pscustomobject]@{
        Status = $status
        Path = $Path
        NewRect = "$targetX,$targetY,$Width,$Height"
        Offset = ("0x{0:X}" -f ($freestyle.Offset - $apdb.DataOffset))
        RemovedMapButton = $null -ne $mapButton
    }

    if ($DryRun) {
        if ($result.Status -eq "Patched") {
            $result.Status = "WouldPatch"
        }
        return $result
    }

    if ($result.Status -eq "AlreadyPatched") {
        return $result
    }

    Save-UiDataBackup $Path $BackupDir $BuildProfile

    Write-U32 $bytes ($freestyle.Offset + 12) ([uint32]$targetX)
    Write-U32 $bytes ($freestyle.Offset + 16) ([uint32]$targetY)
    Write-U32 $bytes ($freestyle.Offset + 20) ([uint32]$Width)
    Write-U32 $bytes ($freestyle.Offset + 24) ([uint32]$Height)

    for ($offset = $freestyle.Offset + 28; $offset -le ($freestyle.EndOffset - 8); $offset += 4) {
        $token = Read-U32 $bytes $offset
        $value = Read-U32 $bytes ($offset + 4)
        if ($token -eq 33 -and $value -eq 17) {
            Write-U32 $bytes ($offset + 4) 77
        }
        if ($token -eq 12 -and $value -eq $IX34) {
            Write-U32 $bytes ($offset + 4) $INPq
        }
        if ($token -eq 13 -and $value -ne $StockFreestyleFrame) {
            Write-U32 $bytes ($offset + 4) $StockFreestyleFrame
        }
    }

    [byte[]]$newBytes = $bytes
    if ($null -ne $mapButton) {
        $removeLength = $mapButton.EndOffset - $mapButton.Offset
        $newBytes = Remove-Bytes $bytes $mapButton.Offset $mapButton.EndOffset
        foreach ($entry in $entries) {
            if ($entry.DataOffset -gt $mapButton.Offset) {
                Write-U32 $newBytes $entry.DataOffsetField ([uint32]($entry.DataOffset - $removeLength))
            }
        }
        Write-U32 $newBytes $apdb.DataSizeField ([uint32]($apdb.DataSize - $removeLength))
    }

    [IO.File]::WriteAllBytes($Path, $newBytes)
    return $result
}

$resolvedGamePath = Get-MajestyPath $GamePath
$dataPath = Join-Path $resolvedGamePath "Data"
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$backupRoot = Join-Path $dataPath $BackupRootName

if (-not (Test-Path -LiteralPath $dataPath)) {
    throw "Could not find Data folder at $dataPath."
}
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$exeBytes = [IO.File]::ReadAllBytes($exePath)
$profile = Get-MajestyBuildProfile $exePath $exeBytes
$backupDir = Join-Path $backupRoot $profile.Id
$exeChecks = @(
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
foreach ($check in $exeChecks) {
    $isStock = Test-BytesEqual $exeBytes $check.Offset $check.Stock
    $isPatched = Test-BytesEqual $exeBytes $check.Offset $check.Patched
    if (-not $isStock -and -not $isPatched) {
        $found = [BitConverter]::ToString($exeBytes, $check.Offset, 4)
        throw ("MajestyHD.exe matches {0}, but has unexpected bytes at file offset 0x{1:X} for {2}. Found {3}." -f $profile.DisplayName, $check.Offset, $check.Name, $found)
    }
}

$uiFiles = Get-ChildItem -LiteralPath $dataPath -Filter "UIData_*.dat" | Sort-Object Name
if ($uiFiles.Count -eq 0) {
    throw "No UIData_*.dat files found in $dataPath."
}

Write-Host "Majesty Gold HD Downloadable Quests Shortcut installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Detected build: $($profile.DisplayName)"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

foreach ($check in @(
    @{ Offset = $profile.FreestyleIconCallbackOffset; Patched = $profile.CustomQuestCallbackBytes; Label = "stock Freestyle callback -> stock Custom Quest callback" },
    @{ Offset = $profile.CustomQuestCompareImmediateOffset; Patched = $FreestyleObjectBytes; Label = "Custom Quest click compare 4034 -> 5000" }
)) {
    $status = if (Test-BytesEqual $exeBytes $check.Offset $check.Patched) { "AlreadyPatched" } else { "WouldPatch" }
    if (-not $DryRun -and $status -eq "WouldPatch") {
        $status = "Patched"
    }
    Write-Host ("MajestyHD.exe: {0} {1} at file offset 0x{2:X}" -f $status, $check.Label, $check.Offset)
}
Write-Host ""

if (-not $DryRun) {
    Assert-FileWritable $exePath
    Assert-FilesWritable $uiFiles
    Import-CompatibleLegacyBackups $backupRoot $backupDir $profile
}

$results = foreach ($file in $uiFiles) {
    Patch-UiDataFile $file.FullName $backupDir $profile
}

foreach ($item in $results) {
    $name = Split-Path -Leaf $item.Path
    if ($item.Status -eq "Patched" -or $item.Status -eq "WouldPatch" -or $item.Status -eq "AlreadyPatched") {
        Write-Host ("{0}: {1} stock Freestyle icon routed to Custom Quests at {2} rect={3}" -f $name, $item.Status, $item.Offset, $item.NewRect)
    } else {
        Write-Host ("{0}: {1} ({2})" -f $name, $item.Status, $item.Reason)
    }
}

if (-not $DryRun) {
    # No whole-file exe backup. The uninstaller reverses these two 4-byte edits
    # instead, which leaves other utilities' patches to the same file intact.
    # The UIData_*.dat backups below are still needed: those are bulk data
    # rewrites, not small hooks, and nothing else touches them.
    Write-Bytes $exeBytes $profile.FreestyleIconCallbackOffset $profile.CustomQuestCallbackBytes
    Write-Bytes $exeBytes $profile.CustomQuestCompareImmediateOffset $FreestyleObjectBytes
    [IO.File]::WriteAllBytes($exePath, $exeBytes)
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete."
} else {
    Write-Host "Done. The circular compass icon opens Downloadable Quests; the Freestyle text label still opens Freestyle."
    Write-Host "Use Uninstall - Restore Original Quest Buttons.bat to undo this patch."
}
