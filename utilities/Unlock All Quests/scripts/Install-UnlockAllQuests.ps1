param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_unlock_all_quests_originals"
$CaveOffset = 0x33432A
$CaveSize = 0xD6
$EligibilityHookOffset = 0x11BC40
$DispatchHookOffset = 0x7A0EE
$ResetRefreshHookOffset = 0x7A278
$VisibilityImmediateOffset = 0x79AED

[byte[]]$EligibilityOriginal = @(0x6A, 0xFF, 0x68, 0x38, 0x33, 0x70, 0x00)
[byte[]]$EligibilityHook = @(0xE9, 0xE5, 0x86, 0x21, 0x00, 0x90, 0x90)
[byte[]]$DispatchOriginal = @(0x81, 0xFB, 0x8A, 0x13, 0x00, 0x00)
[byte[]]$DispatchHook = @(0xE9, 0x4F, 0xA2, 0x2B, 0x00, 0x90)
[byte[]]$ResetRefreshOriginal = @(0x33, 0xF6, 0x39, 0x9C, 0x24, 0xB4, 0x00, 0x00, 0x00)
[byte[]]$ResetRefreshHook = @(0xE9, 0xFD, 0xA0, 0x2B, 0x00, 0x90, 0x90, 0x90, 0x90)

function Save-PreInstallBackup {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$BackupDir,
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$UtilityName
    )

    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    if (Test-Path -LiteralPath $BackupPath) {
        return
    }

    Copy-Item -LiteralPath $SourcePath -Destination $BackupPath

    # Say plainly what this copy is. It is NOT a stock game file, and the
    # uninstaller never reads it: uninstalling reverses this utility's own byte
    # changes. Without this note the filename alone implies otherwise.
    $leaf = Split-Path -Leaf $BackupPath
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $note = @"
$leaf

A copy of MajestyHD.exe taken immediately before $UtilityName was first
installed, on $stamp.

This is NOT guaranteed to be an unmodified Majesty Gold HD executable. It is
whatever was on disk at that moment, which may already include other patches
you had installed.

You do not need this file to uninstall. The uninstaller reverses its own byte
changes and never reads this copy. It is kept only as a convenience snapshot.

For a guaranteed clean executable, use Steam instead:
  Right-click Majesty Gold HD > Properties > Installed Files >
  Verify integrity of game files
"@
    Set-Content -LiteralPath (Join-Path $BackupDir "READ ME - what this file is.txt") -Value $note -Encoding ASCII
}

function Get-PatchBlob {
    # The quest map is rebuilt by the stock routine at VA 0x0047A1D0. Reset
    # Quests already redraws its clouds correctly because the stock code calls
    # that routine at VA 0x0047AE70, immediately before this patch's own
    # continuation hook. Earlier revisions instead hand-rolled a per-control
    # refresh loop, which updated state but never repainted, so the clouds only
    # changed on leaving and re-entering the map.
    #
    # Both hooks now set or clear the session flag and then call the same stock
    # rebuild. ECX holds the quest-map object in EDI at both hook sites, which
    # is the register the stock Reset path passes.
    [byte[]]$blob = New-Object byte[] $CaveSize

    # Eligibility hook at VA 0x734F2A. If the process-local byte at 0x7C25F4
    # is set, the game's normal IsQuestUnlocked predicate returns true.
    [byte[]]$eligibilityStub = @(
        0xA0, 0xF4, 0x25, 0x7C, 0x00,
        0x84, 0xC0,
        0x74, 0x03,
        0xC2, 0x04, 0x00,
        0x6A, 0xFF,
        0x68, 0x38, 0x33, 0x70, 0x00,
        0xE9, 0x05, 0x79, 0xDE, 0xFF
    )

    # Click dispatcher at VA 0x734F42. Control 0x29A sets the unlock flag and
    # runs the stock quest-map rebuild, then rejoins the handled path.
    [byte[]]$dispatchStub = @(
        0x66,0x81,0xFB,0x9A,0x02,   # cmp   bx, 0x29A
        0x75,0x19,                  # jne   passthrough
        0x88,0x1D,0xF4,0x25,0x7C,0x00,  # mov   [0x7C25F4], bl
        0x60,                       # pushad
        0x6A,0x00,                  # push  0
        0x89,0xF9,                  # mov   ecx, edi
        0xE8,0x77,0x52,0xD4,0xFF,   # call  0x0047A1D0
        0x83,0xC4,0x04,             # add   esp, 4
        0x61,                       # popad
        0xE9,0x13,0x5C,0xD4,0xFF,   # jmp   0x0047AB75
        0x81,0xFB,0x8A,0x13,0x00,0x00,  # cmp   ebx, 0x138A  (displaced)
        0xE9,0x87,0x5D,0xD4,0xFF    # jmp   0x0047ACF4
    )

    # Reset Quests continuation at VA 0x734F7A. Clears the flag, then runs the
    # same rebuild so the clouds come back without leaving the map.
    [byte[]]$resetRefreshStub = @(
        0x60,                       # pushad
        0x31,0xC0,                  # xor   eax, eax
        0xA2,0xF4,0x25,0x7C,0x00,   # mov   [0x7C25F4], al
        0x6A,0x00,                  # push  0
        0x89,0xF9,                  # mov   ecx, edi
        0xE8,0x45,0x52,0xD4,0xFF,   # call  0x0047A1D0
        0x83,0xC4,0x04,             # add   esp, 4
        0x61,                       # popad
        0x31,0xF6,                  # xor   esi, esi              (displaced)
        0x39,0x9C,0x24,0xB4,0x00,0x00,0x00,  # cmp [esp+0xB4], ebx (displaced)
        0xE9,0xE4,0x5E,0xD4,0xFF    # jmp   0x0047AE81
    )

    [Array]::Copy($eligibilityStub, 0, $blob, 0x00, $eligibilityStub.Length)
    [Array]::Copy($dispatchStub, 0, $blob, 0x18, $dispatchStub.Length)
    [Array]::Copy($resetRefreshStub, 0, $blob, 0x50, $resetRefreshStub.Length)
    return $blob
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
    if ($null -eq $Patch -or $Patch.Length -eq 0) { throw "Internal error: empty patch." }
    if ($Offset -lt 0 -or ($Offset + $Patch.Length) -gt $Bytes.Length) {
        throw ("Patch range at 0x{0:X} falls outside MajestyHD.exe." -f $Offset)
    }
    [Array]::Copy($Patch, 0, $Bytes, $Offset, $Patch.Length)
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
    if (-not (Test-BytesEqual $Bytes 0 $magic)) { throw "Not a Majesty UIData archive." }
    $entries = @()
    for ($section = 0; $section -lt (Read-U32 $Bytes 12); $section++) {
        $directory = 20 + ($section * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $directory, 4).TrimEnd()
        $header = [int](Read-U32 $Bytes ($directory + 4))
        for ($index = 0; $index -lt (Read-U32 $Bytes $header); $index++) {
            $entryHeader = $header + 8 + ($index * 28)
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

function Find-ByteSequence {
    param([byte[]]$Bytes, [int]$Start, [int]$End, [byte[]]$Needle)
    for ($offset = $Start; $offset -le ($End - $Needle.Length); $offset++) {
        if (Test-BytesEqual $Bytes $offset $Needle) { return $offset }
    }
    return -1
}

function Patch-QuestButtonLabel {
    param([string]$Path, [switch]$InspectOnly)
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    $entries = Get-CamEntries $bytes
    $apdb = $entries | Where-Object { $_.Extension -eq "SMNU" -and $_.Name -eq "APdb" } | Select-Object -First 1
    if ($null -eq $apdb) { return [pscustomobject]@{ Status="Skipped"; Path=$Path; Reason="No modern APdb quest menu." } }
    $strings = $entries | Where-Object { $_.Extension -eq "STRT" -and $_.Name -eq "APdb" } | Select-Object -First 1
    if ($null -eq $strings) { throw "No APdb string table in $(Split-Path -Leaf $Path)." }

    [byte[]]$stock = [Text.Encoding]::ASCII.GetBytes("Cheat All Quests`0")
    [byte[]]$patched = [Text.Encoding]::ASCII.GetBytes("Unlock All Quests`0")
    $start = $strings.DataOffset
    $end = $strings.DataOffset + $strings.DataSize
    $patchedOffset = Find-ByteSequence $bytes $start $end $patched
    if ($patchedOffset -ge 0) { return [pscustomobject]@{ Status="AlreadyPatched"; Path=$Path } }
    $stockOffset = Find-ByteSequence $bytes $start $end $stock
    if ($stockOffset -lt 0) { throw "Could not find the stock Cheat All Quests label in $(Split-Path -Leaf $Path)." }
    if ($DryRun -or $InspectOnly) { return [pscustomobject]@{ Status="WouldPatch"; Path=$Path } }

    $delta = $patched.Length - $stock.Length
    [byte[]]$newBytes = New-Object byte[] ($bytes.Length + $delta)
    [Array]::Copy($bytes, 0, $newBytes, 0, $stockOffset)
    [Array]::Copy($patched, 0, $newBytes, $stockOffset, $patched.Length)
    [Array]::Copy($bytes, $stockOffset + $stock.Length, $newBytes, $stockOffset + $patched.Length, $bytes.Length - ($stockOffset + $stock.Length))
    foreach ($entry in $entries) {
        if ($entry.DataOffset -gt $stockOffset) {
            Write-U32 $newBytes $entry.DataOffsetField ([uint32]($entry.DataOffset + $delta))
        }
    }
    Write-U32 $newBytes $strings.DataSizeField ([uint32]($strings.DataSize + $delta))
    [IO.File]::WriteAllBytes($Path, $newBytes)
    return [pscustomobject]@{ Status="Patched"; Path=$Path }
}

function Get-MajestyPath {
    param([string]$RequestedPath)
    if ($RequestedPath) { return $RequestedPath }
    if (Test-Path -LiteralPath $DefaultGamePath) { return $DefaultGamePath }

    $appId = 73230
    $searched = New-Object System.Collections.Generic.List[string]
    $searched.Add($DefaultGamePath)
    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM:\SOFTWARE\Valve\Steam",
        "HKCU:\SOFTWARE\Valve\Steam"
    )) {
        try {
            $installPath = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($installPath) { $steamRoots.Add($installPath) }
        } catch {}
    }

    $libraryRoots = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in $steamRoots) {
        $libraryRoots.Add($steamRoot)
        $libraryFile = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libraryFile) {
            foreach ($line in Get-Content -LiteralPath $libraryFile) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $libraryRoots.Add(($Matches[1] -replace '\\\\', '\'))
                }
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
    throw ("Could not find Majesty Gold HD." + [Environment]::NewLine + "Looked in:" + [Environment]::NewLine + $lines)
}

function Assert-FileWritable {
    param([string]$Path)
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch {
        throw "Cannot modify $(Split-Path -Leaf $Path). Close Majesty and try again. If needed, run the BAT as administrator."
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
if (-not (Test-Path -LiteralPath $exePath)) { throw "Could not find MajestyHD.exe at $exePath." }

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
[byte[]]$patchBlob = Get-PatchBlob
$uiFiles = @(Get-ChildItem -LiteralPath (Join-Path $resolvedGamePath "Data") -Filter "UIData_*.dat" | Sort-Object Name)

$eligibilityStock = Test-BytesEqual $bytes $EligibilityHookOffset $EligibilityOriginal
$eligibilityPatched = Test-BytesEqual $bytes $EligibilityHookOffset $EligibilityHook
$dispatchStock = Test-BytesEqual $bytes $DispatchHookOffset $DispatchOriginal
$dispatchPatched = Test-BytesEqual $bytes $DispatchHookOffset $DispatchHook
$resetStock = Test-BytesEqual $bytes $ResetRefreshHookOffset $ResetRefreshOriginal
$resetPatched = Test-BytesEqual $bytes $ResetRefreshHookOffset $ResetRefreshHook
$visibilityStock = $bytes[$VisibilityImmediateOffset] -eq 0
$visibilityPatched = $bytes[$VisibilityImmediateOffset] -eq 1
$caveStock = Test-ZeroRange $bytes $CaveOffset $CaveSize
$cavePatched = Test-BytesEqual $bytes $CaveOffset $patchBlob

if (-not $eligibilityStock -and -not $eligibilityPatched) {
    throw ("Unexpected quest-eligibility bytes at file offset 0x{0:X}." -f $EligibilityHookOffset)
}
if (-not $dispatchStock -and -not $dispatchPatched) {
    throw ("Unexpected quest-menu dispatch bytes at file offset 0x{0:X}." -f $DispatchHookOffset)
}
if (-not $resetStock -and -not $resetPatched) {
    throw ("Unexpected Reset Quests bytes at file offset 0x{0:X}." -f $ResetRefreshHookOffset)
}
if (-not $visibilityStock -and -not $visibilityPatched) {
    throw ("Unexpected Cheat All Quests visibility byte at file offset 0x{0:X}." -f $VisibilityImmediateOffset)
}
if (-not $caveStock -and -not $cavePatched) {
    throw ("The unlock-all code-cave range at file offset 0x{0:X} is already in use." -f $CaveOffset)
}

$freshState = $eligibilityStock -and $dispatchStock -and $resetStock -and $visibilityStock -and $caveStock
$patchedState = $eligibilityPatched -and $dispatchPatched -and $resetPatched -and $visibilityPatched -and $cavePatched
if (-not $freshState -and -not $patchedState) {
    throw "MajestyHD.exe contains only part of a recognized Unlock All Quests patch. Refusing to guess at a repair."
}

$labelResults = foreach ($file in $uiFiles) { Patch-QuestButtonLabel $file.FullName -InspectOnly }
Write-Host "Majesty Gold HD Unlock All Quests installer"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($DryRun) {
    $verb = if ($patchedState) { "leave installed" } else { "install" }
    Write-Host "MajestyHD.exe: would $verb Unlock All Quests."
    foreach ($result in $labelResults) { Write-Host ("{0}: {1}" -f (Split-Path -Leaf $result.Path), $result.Status) }
    return
}

Assert-FileWritable $exePath
foreach ($result in $labelResults | Where-Object { $_.Status -eq "WouldPatch" }) { Assert-FileWritable $result.Path }

$backupDir = Join-Path $resolvedGamePath $BackupDirName
Save-PreInstallBackup $exePath $backupDir (Join-Path $backupDir "MajestyHD.exe") "Unlock All Quests"

Write-Bytes $bytes $CaveOffset $patchBlob
Write-Bytes $bytes $EligibilityHookOffset $EligibilityHook
Write-Bytes $bytes $DispatchHookOffset $DispatchHook
Write-Bytes $bytes $ResetRefreshHookOffset $ResetRefreshHook
$bytes[$VisibilityImmediateOffset] = 1
[IO.File]::WriteAllBytes($exePath, $bytes)

$labelResults = foreach ($file in $uiFiles) { Patch-QuestButtonLabel $file.FullName }

Write-Host ("MajestyHD.exe: {0}." -f $(if ($patchedState) { "already patched" } else { "patched" }))
Write-Host "Quest-map label: UNLOCK ALL QUESTS."
Write-Host "Done. Reset Quests now clears the session unlock and restores normal locks."
