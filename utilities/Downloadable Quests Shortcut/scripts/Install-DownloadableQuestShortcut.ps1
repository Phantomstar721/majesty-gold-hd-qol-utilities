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
$FreestyleCallbackBytes = [byte[]](0x00, 0x93, 0x47, 0x00)
$CustomQuestCallbackBytes = [byte[]](0x00, 0x92, 0x47, 0x00)
$CustomQuestObjectBytes = [byte[]](0xC2, 0x0F, 0x00, 0x00)
$FreestyleObjectBytes = [byte[]](0x88, 0x13, 0x00, 0x00)
$FreestyleIconCallbackOffset = 0x798B6
$CustomQuestCompareImmediateOffset = 0x7A0FE
$StockFreestyleFrame = 1039

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

    if ($Bytes.Length -lt ($Offset + $Expected.Length)) {
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
        throw "Cannot patch $name because it is in use or not writable. Close Majesty Gold HD and run this installer again. If the game is closed, right-click the BAT and choose Run as administrator."
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

function Patch-UiDataFile {
    param([string]$Path, [string]$BackupDir)

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

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    $backupPath = Join-Path $BackupDir ((Split-Path -Leaf $Path) + ".original")
    if (-not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $Path -Destination $backupPath
    }

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
$backupDir = Join-Path $dataPath "_custom_quest_button_originals"

if (-not (Test-Path -LiteralPath $dataPath)) {
    throw "Could not find Data folder at $dataPath."
}
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$exeBytes = [IO.File]::ReadAllBytes($exePath)
foreach ($check in @(
    @{ Offset = $FreestyleIconCallbackOffset; Stock = $FreestyleCallbackBytes; Patched = $CustomQuestCallbackBytes; Name = "Freestyle icon hover callback" },
    @{ Offset = $CustomQuestCompareImmediateOffset; Stock = $CustomQuestObjectBytes; Patched = $FreestyleObjectBytes; Name = "Custom Quest click compare" }
)) {
    $isStock = Test-BytesEqual $exeBytes $check.Offset $check.Stock
    $isPatched = Test-BytesEqual $exeBytes $check.Offset $check.Patched
    if (-not $isStock -and -not $isPatched) {
        $found = [BitConverter]::ToString($exeBytes, $check.Offset, 4)
        throw ("MajestyHD.exe does not match the expected Steam build at file offset 0x{0:X} for {1}. Found {2}." -f $check.Offset, $check.Name, $found)
    }
}

$uiFiles = Get-ChildItem -LiteralPath $dataPath -Filter "UIData_*.dat" | Sort-Object Name
if ($uiFiles.Count -eq 0) {
    throw "No UIData_*.dat files found in $dataPath."
}

Write-Host "Majesty Gold HD Downloadable Quests Shortcut installer"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

foreach ($check in @(
    @{ Offset = $FreestyleIconCallbackOffset; Patched = $CustomQuestCallbackBytes; Label = "Freestyle icon hover callback 0x479300 -> 0x479200" },
    @{ Offset = $CustomQuestCompareImmediateOffset; Patched = $FreestyleObjectBytes; Label = "Custom Quest click compare 4034 -> 5000" }
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
}

$results = foreach ($file in $uiFiles) {
    Patch-UiDataFile $file.FullName $backupDir
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
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir | Out-Null
    }
    $exeBackup = Join-Path $backupDir "MajestyHD.exe.original"
    if (-not (Test-Path -LiteralPath $exeBackup)) {
        Copy-Item -LiteralPath $exePath -Destination $exeBackup
    }
    Write-Bytes $exeBytes $FreestyleIconCallbackOffset $CustomQuestCallbackBytes
    Write-Bytes $exeBytes $CustomQuestCompareImmediateOffset $FreestyleObjectBytes
    [IO.File]::WriteAllBytes($exePath, $exeBytes)
}

Write-Host ""
if ($DryRun) {
    Write-Host "Dry run complete."
} else {
    Write-Host "Done. The circular compass icon opens Downloadable Quests; the Freestyle text label still opens Freestyle."
    Write-Host "Use Uninstall - Restore Original Quest Buttons.bat to undo this patch."
}
