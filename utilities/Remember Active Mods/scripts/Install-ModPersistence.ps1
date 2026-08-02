param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "NativePathEncoding.ps1")

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$BackupDirName = "_mod_persistence_originals"

# PE section characteristics: code, execute, read. This utility keeps its state in .data, so its section does not need to be writable.
$SectionCharacteristics = 1610612768  # 0x60000020: code, execute, read

$SectionName = ".mpst"
$LoadCallOffset = 0x77D30
$LoadCallVa = 0x478930
$SaveCallOffset = 0x124196
$SaveCallVa = 0x524D96
$ApplyActiveModsVa = 0x525540

$PatchVirtualSize = 0x11AF
$PatchRawSize = 0x1200

# The patch blob is assembled with its own string addresses and calls to stock
# Majesty routines baked in, assuming .mpst lands at 0x80E000. That is the
# placement you get when this is the first utility installed on a stock exe,
# but it is not guaranteed any more.
#
# New-PatchBlob relocates the blob to wherever the section actually lands. Six
# dwords reference strings inside the section. Relative branches whose
# targets remain inside the blob relocate for free; calls to stock executable
# routines are rewritten separately below.
$BlobAssumedVa = 0x80E000

# Where each baked-in string reference points, and where the string actually
# ends up. Everything except the preference path stays put.
#
# The preference path moves. It used to be the bare filename
# "MajestyModPersistence.txt" in a 0x28-byte slot at 0x180, which fopen resolves
# against the process working directory. For a Steam launch that is the game
# folder under Program Files, which a standard user cannot write, so the active
# mod list silently never persisted. Remember Game Speed already had this fixed;
# the fix was never carried across.
#
# An absolute path does not fit at 0x180, so it moves to 0x600 where there is
# free space up to the 0x11AF virtual size, and the two references to it are
# repointed by the relocation pass below.
$BlobStringMoves = @(
    [pscustomobject]@{ From = 0x180; To = 0x600 },
    [pscustomobject]@{ From = 0x1A8; To = 0x1A8 },
    [pscustomobject]@{ From = 0x1AB; To = 0x1AB },
    [pscustomobject]@{ From = 0x1F0; To = 0x1F0 },
    [pscustomobject]@{ From = 0x200; To = 0x200 }
)
$PreferencePathBlobOffset = 0x600

[byte[]]$OriginalLoadCall = @(0xE8, 0xAB, 0xCA, 0x0A, 0x00)
[byte[]]$OriginalSaveCall = @(0xE8, 0xA5, 0x07, 0x00, 0x00)

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

function New-RelativeCallBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE8
    [BitConverter]::GetBytes($relative).CopyTo($result, 1)
    return $result
}

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

function New-SectionHeader {
    param(
        [string]$Name,
        [uint32]$VirtualSize,
        [uint32]$Rva,
        [uint32]$RawSize,
        [uint32]$RawOffset
    )

    $bytes = New-Object byte[] 40
    [Text.Encoding]::ASCII.GetBytes($Name).CopyTo($bytes, 0)
    [BitConverter]::GetBytes($VirtualSize).CopyTo($bytes, 8)
    [BitConverter]::GetBytes($Rva).CopyTo($bytes, 12)
    [BitConverter]::GetBytes($RawSize).CopyTo($bytes, 16)
    [BitConverter]::GetBytes($RawOffset).CopyTo($bytes, 20)
    [BitConverter]::GetBytes([uint32]$SectionCharacteristics).CopyTo($bytes, 36)
    return $bytes
}

function New-PatchBlob {
    param(
        [uint32]$PatchVa,
        [Parameter(Mandatory = $true)][byte[]]$PreferencePathBytes
    )

    $bytes = New-Object byte[] $PatchRawSize

    function Set-Bytes {
        param([int]$Offset, [byte[]]$Patch)
        for ($i = 0; $i -lt $Patch.Length; $i++) {
            $bytes[$Offset + $i] = $Patch[$i]
        }
    }

    function Set-AsciiZ {
        param([int]$Offset, [string]$Text)
        $raw = [Text.Encoding]::ASCII.GetBytes($Text)
        Set-Bytes $Offset $raw
        $bytes[$Offset + $raw.Length] = 0
    }

    Set-Bytes 0x00 ([byte[]]@(
        0xE8, 0x3B, 0x75, 0xD1, 0xFF,       # call original Mods OK handler
        0x60,                               # pushad
        0x68, 0xA8, 0xE1, 0x80, 0x00,       # push "wb"
        0x68, 0x80, 0xE1, 0x80, 0x00,       # push "MajestyModPersistence.txt"
        0xFF, 0x15, 0x30, 0x54, 0x73, 0x00, # call fopen
        0x83, 0xC4, 0x08,                   # add esp, 8
        0x85, 0xC0,                         # test eax, eax
        0x74, 0x6B,                         # je done
        0x89, 0xC3,                         # mov ebx, eax
        0x8B, 0x35, 0x4C, 0x1E, 0x7C, 0x00, # mov esi, [active-list sentinel]
        0x85, 0xF6,                         # test esi, esi
        0x74, 0x55,                         # je close_file
        0x8B, 0x3E,                         # mov edi, [esi]
        0x39, 0xF7,                         # cmp edi, esi
        0x74, 0x4F,                         # je close_file
        0x8B, 0x47, 0x08,                   # mov eax, [edi+8]
        0x85, 0xC0,                         # test eax, eax
        0x74, 0x44,                         # je next_node
        0x0F, 0xB6, 0x48, 0x13,             # movzx ecx, byte ptr [eax+0x13]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x12,             # movzx ecx, byte ptr [eax+0x12]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x11,             # movzx ecx, byte ptr [eax+0x11]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x10,             # movzx ecx, byte ptr [eax+0x10]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0F,             # movzx ecx, byte ptr [eax+0x0f]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0E,             # movzx ecx, byte ptr [eax+0x0e]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0D,             # movzx ecx, byte ptr [eax+0x0d]
        0x51,                               # push ecx
        0x0F, 0xB6, 0x48, 0x0C,             # movzx ecx, byte ptr [eax+0x0c]
        0x51,                               # push ecx
        0x0F, 0xB7, 0x48, 0x0A,             # movzx ecx, word ptr [eax+0x0a]
        0x51,                               # push ecx
        0x0F, 0xB7, 0x48, 0x08,             # movzx ecx, word ptr [eax+0x08]
        0x51,                               # push ecx
        0xFF, 0x70, 0x04,                   # push [eax+0x04]
        0x68, 0xAB, 0xE1, 0x80, 0x00,       # push "%s\r\n"
        0x53,                               # push ebx
        0xFF, 0x15, 0xE0, 0x53, 0x73, 0x00, # call fprintf
        0x83, 0xC4, 0x34,                   # add esp, 52
        0x8B, 0x3F,                         # mov edi, [edi]
        0xEB, 0xAD,                         # jmp loop_start
        0x53,                               # push ebx
        0xFF, 0x15, 0x44, 0x54, 0x73, 0x00, # call fclose
        0x83, 0xC4, 0x04,                   # add esp, 4
        0x61,                               # popad
        0xC3                                # ret
    ))

    # The load-hook restore routine is NOT hand-assembled here. A 488-byte
    # hand-written version used to be written to 0x300 at this point and was
    # then unconditionally overwritten a few lines below by the 573-byte
    # $loadRestoreBlob, so editing it changed nothing. The blob is the only
    # source of truth. The removed listing is in git history if it is ever
    # needed as a reference.

    # Load hook restore build. It reads saved GUIDs, finds matching installed
    # mods, and appends them to Majesty's Active list after startup. It first
    # checks the Active list so repeated startup/menu calls do not duplicate
    # the same mod in memory or in the saved preset file.
    [byte[]]$loadRestoreBlob = [Convert]::FromBase64String("/3QkCP90JAjo03DR/4PECGBo8OGAAGiA4YAA/xUwVHMAg8QIhcAPhAgCAACJw1No/wMAAGoBaADZewD/FTRUcwCDxBCJxlP/FURUcwCDxASF9g+E3AEAAMaGANl7AAC+ANl7AIoGhMAPhMYBAAA8IHcGRuns////aCjdewBoJN17AGgg3XsAaBzdewBoGN17AGgU3XsAaBDdewBoDN17AGgI3XsAaATdewBoAN17AGgA4oAAVv8VTFRzAIPENIP4Cw+FTwEAAIsVMB58AIXSD4RBAQAAizo51w+ENwEAAItHCIXAD4QlAQAAiw0A3XsAOUgED4UWAQAAD7dICDsNBN17AA+FBgEAAA+3SAo7DQjdewAPhfYAAAAPtkgMOw0M3XsAD4XmAAAAD7ZIDTsNEN17AA+F1gAAAA+2SA47DRTdewAPhcYAAAAPtkgPOw0Y3XsAD4W2AAAAD7ZIEDsNHN17AA+FpgAAAA+2SBE7DSDdewAPhZYAAAAPtkgSOw0k3XsAD4WGAAAAD7ZIEzsNKN17AA+FdgAAAKMs3XsAVosNTB58AIXJD4QcAAAAizk5zw+EEgAAAItXCDnQD4RHAAAAiz/p5v///6FMHnwAhcAPhDMAAACLUASNWARoLN17AFJQuTgefADoUz7R/2oBuTgefACJxej1PtH/iSuLRQSJKMYF/B18AAFe6QcAAACLP+nB/v//igaEwA+EFAAAADwKdAo8DXQGRuno////Rukw/v//YcM=")
    if ($loadRestoreBlob.Length -lt 2 -or
        $loadRestoreBlob[$loadRestoreBlob.Length - 2] -ne 0x61 -or
        $loadRestoreBlob[$loadRestoreBlob.Length - 1] -ne 0xC3) {
        throw "Load restore blob no longer ends in popad/ret. Refusing to inject the active-mod commit call at an unknown location."
    }

    # After rebuilding the UI's Active list, drive the same canonical commit
    # routine called by the Mods screen's OK handler. This copies the selected
    # entries into Majesty's effective mod configuration, which is what later
    # quest loads use to register XML descriptions and other custom data.
    # Merely linking Active-list nodes makes a mod look selected but loses its
    # custom registrations after the main-menu teardown.
    [byte[]]$commitTail = New-Object byte[] 9
    $commitTail[0] = 0xB8 # mov eax, ApplyActiveModsVa
    [BitConverter]::GetBytes([uint32]$ApplyActiveModsVa).CopyTo($commitTail, 1)
    $commitTail[5] = 0xFF # call eax
    $commitTail[6] = 0xD0
    $commitTail[7] = 0x61 # popad
    $commitTail[8] = 0xC3 # ret
    [byte[]]$committingLoadRestoreBlob = New-Object byte[] ($loadRestoreBlob.Length + 7)
    [Array]::Copy(
        $loadRestoreBlob,
        0,
        $committingLoadRestoreBlob,
        0,
        $loadRestoreBlob.Length - 2
    )
    $commitTail.CopyTo($committingLoadRestoreBlob, $loadRestoreBlob.Length - 2)
    Set-Bytes 0x300 $committingLoadRestoreBlob

    Set-Bytes $PreferencePathBlobOffset $PreferencePathBytes
    $bytes[$PreferencePathBlobOffset + $PreferencePathBytes.Length] = 0
    Set-AsciiZ 0x1A8 "wb"
    Set-AsciiZ 0x1AB "%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X`r`n"
    Set-AsciiZ 0x1F0 "rb"
    Set-AsciiZ 0x200 "%8x-%4x-%4x-%2x%2x-%2x%2x%2x%2x%2x%2x"

    # Rewrite calls from the appended section to fixed routines in the stock
    # executable. Unlike branches within the blob, these rel32 operands do not
    # remain correct when another utility causes .mpst to land at a later VA.
    $externalCalls = @(
        [pscustomobject]@{ Offset = 0x000; Target = $ApplyActiveModsVa },
        [pscustomobject]@{ Offset = 0x308; Target = 0x5253E0 },
        [pscustomobject]@{ Offset = 0x4E8; Target = 0x522340 },
        [pscustomobject]@{ Offset = 0x4F6; Target = 0x5223F0 }
    )
    foreach ($externalCall in $externalCalls) {
        Set-Bytes $externalCall.Offset (
            New-RelativeCallBytes `
                ([uint32]($PatchVa + $externalCall.Offset)) `
                ([uint32]$externalCall.Target)
        )
    }
    foreach ($externalCall in $externalCalls) {
        if ($bytes[$externalCall.Offset] -ne 0xE8) {
            throw ("Expected a rel32 call at patch offset 0x{0:X}." -f $externalCall.Offset)
        }
        $relative = [BitConverter]::ToInt32($bytes, $externalCall.Offset + 1)
        $actualTarget = [int64]$PatchVa + $externalCall.Offset + 5 + $relative
        if ($actualTarget -ne $externalCall.Target) {
            throw (
                "Relocated call at patch offset 0x{0:X} targets 0x{1:X}, expected 0x{2:X}." -f
                $externalCall.Offset, $actualTarget, $externalCall.Target
            )
        }
    }

    # Rebase every baked-in string reference to where the string actually lives.
    # This handles two things at once: the section landing at a different VA,
    # and the preference path having moved to a roomier slot. Collect all
    # matches against the pristine blob first, then apply, so a rewritten value
    # can never be picked up as a later match.
    #
    # Runs unconditionally. Even when the section lands at its assumed VA, the
    # preference path still has to be repointed from 0x180 to its new home.
    $relocations = @()
    foreach ($move in $BlobStringMoves) {
        $from = [BitConverter]::GetBytes([uint32]($BlobAssumedVa + $move.From))
        $to = [uint32]($PatchVa + $move.To)
        $found = 0
        for ($i = 0; $i -le ($bytes.Length - 4); $i++) {
            if ($bytes[$i] -eq $from[0] -and $bytes[$i + 1] -eq $from[1] -and
                $bytes[$i + 2] -eq $from[2] -and $bytes[$i + 3] -eq $from[3]) {
                $relocations += [pscustomobject]@{ Offset = $i; Value = $to }
                $found++
                $i += 3
            }
        }
        if ($found -eq 0) {
            throw ("Mod persistence relocation failed: nothing referenced the blob string at 0x{0:X}. The patch blob changed without updating `$BlobStringMoves." -f $move.From)
        }
    }
    if ($relocations.Count -ne 6) {
        throw ("Mod persistence relocation expected 6 self-references but found {0}. Refusing to build a patch that may point at the wrong data." -f $relocations.Count)
    }
    foreach ($relocation in $relocations) {
        [BitConverter]::GetBytes($relocation.Value).CopyTo($bytes, $relocation.Offset)
    }

    return $bytes
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

function Test-ZeroRange {
    param([byte[]]$Bytes, [int]$Offset, [int]$Length)

    if ($Offset -lt 0 -or ($Offset + $Length) -gt $Bytes.Length) {
        return $false
    }
    for ($i = 0; $i -lt $Length; $i++) {
        if ($Bytes[$Offset + $i] -ne 0) {
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
$backupDir = Join-Path $resolvedGamePath $BackupDirName
# Named for what it actually is. The old ".original" name implied a stock
# executable, which it is not: it is whatever was on disk before this utility
# ran, patches from other utilities included.
$backupPath = Join-Path $backupDir "MajestyHD.exe.before-remember-active-mods"
$preferenceDir = Join-Path (
    [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
) "MajestyHD"
$preferencePath = Join-Path $preferenceDir "MajestyModPersistence.txt"
$legacyPreferencePath = Join-Path $resolvedGamePath "MajestyModPersistence.txt"
[byte[]]$preferencePathBytes = ConvertTo-MajestyNarrowPathBytes `
    -Path $preferencePath `
    -UtilityName "Remember Active Mods"
if ($preferencePathBytes.Length -ge 0x100) {
    throw "The Remember Active Mods preference path is too long to embed safely: $preferencePath. No game files were changed."
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$pe = Get-PeInfo $bytes
$existingSection = $pe.Sections | Where-Object { $_.Name -eq $SectionName } | Select-Object -First 1

# Placement is derived from the PE header, so this utility no longer has to be
# the first one installed. It can append its section after any other patch.
if ($existingSection) {
    $patchSectionRva = [uint32]$existingSection.Rva
    $patchSectionRawOffset = [uint32]$existingSection.RawOffset
    $patchSectionHeaderOffset = [int]$existingSection.HeaderOffset
} else {
    $lastSection = $pe.Sections | Sort-Object RawOffset | Select-Object -Last 1
    $patchSectionRawOffset = Align-Value ([uint32]$bytes.Length) ([uint32]$pe.FileAlignment)
    $lastVirtualEnd = [uint32]($lastSection.Rva + [Math]::Max($lastSection.VirtualSize, $lastSection.RawSize))
    $patchSectionRva = Align-Value $lastVirtualEnd ([uint32]$pe.SectionAlignment)
    $patchSectionHeaderOffset = [int]($pe.SectionTableOffset + ($pe.SectionCount * 40))

    if (($patchSectionHeaderOffset + 40) -gt $pe.SizeOfHeaders) {
        throw "No room remains in the PE header for another patch section."
    }
    if (-not (Test-ZeroRange $bytes $patchSectionHeaderOffset 40)) {
        throw ("The PE header slot at file offset 0x{0:X} is not empty. Refusing to add a patch section." -f $patchSectionHeaderOffset)
    }
    if ($patchSectionRawOffset -ne $bytes.Length) {
        throw ("MajestyHD.exe has unaligned trailing data. Expected the new section at 0x{0:X}, but the file ends at 0x{1:X}." -f $patchSectionRawOffset, $bytes.Length)
    }
}

$patchSectionVa = [uint32]($pe.ImageBase + $patchSectionRva)
$patchedFileSize = [int]($patchSectionRawOffset + $PatchRawSize)
$PatchSectionHeader = New-SectionHeader $SectionName $PatchVirtualSize $patchSectionRva $PatchRawSize $patchSectionRawOffset
$patchBlob = New-PatchBlob $patchSectionVa $preferencePathBytes
[byte[]]$PatchedSaveCall = New-RelativeCallBytes $SaveCallVa $patchSectionVa
[byte[]]$PatchedLoadCall = New-RelativeCallBytes $LoadCallVa ($patchSectionVa + 0x300)
$newSizeOfImage = Align-Value ([uint32]($patchSectionRva + $PatchVirtualSize)) ([uint32]$pe.SectionAlignment)

$headerAlreadyPatched = [bool]$existingSection -and (Test-BytesEqual $bytes $patchSectionHeaderOffset $PatchSectionHeader)
$sectionsAlreadyPatched = $headerAlreadyPatched
$loadAlreadyPatched = Test-BytesEqual $bytes $LoadCallOffset $PatchedLoadCall
$loadIsStock = Test-BytesEqual $bytes $LoadCallOffset $OriginalLoadCall
$saveAlreadyPatched = Test-BytesEqual $bytes $SaveCallOffset $PatchedSaveCall
$saveIsStock = Test-BytesEqual $bytes $SaveCallOffset $OriginalSaveCall
$blobAlreadyPatched = [bool]$existingSection -and (Test-BytesEqual $bytes $patchSectionRawOffset $patchBlob)

if (-not $saveAlreadyPatched -and -not $saveIsStock) {
    throw ("MajestyHD.exe is not the expected Steam build near file offset 0x{0:X}, or another patch already owns the mod-save hook." -f $SaveCallOffset)
}
if (-not $loadAlreadyPatched -and -not $loadIsStock) {
    throw ("MajestyHD.exe is not the expected Steam build near file offset 0x{0:X}, or another patch already owns the mod-load hook." -f $LoadCallOffset)
}
if ($existingSection -and $bytes.Length -lt $patchedFileSize) {
    throw ("MajestyHD.exe already has the mod persistence section, but its file size is only 0x{0:X}. Expected at least 0x{1:X}." -f $bytes.Length, $patchedFileSize)
}

Write-Host "Majesty Gold HD Mod Persistence installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Preset file: $preferencePath"
Write-Host "Mode: remember Active mods across launches"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($sectionsAlreadyPatched -and $headerAlreadyPatched -and $saveAlreadyPatched -and $loadAlreadyPatched -and $blobAlreadyPatched) {
    Write-Host "MajestyHD.exe: Remember Active Mods is already installed."
    return
}

if ($DryRun) {
    if (-not $sectionsAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would add .mpst section header at file offset 0x{0:X}." -f $patchSectionHeaderOffset)
        Write-Host ("MajestyHD.exe: would append .mpst section data at file offset 0x{0:X}." -f $patchSectionRawOffset)
    } else {
        Write-Host ("MajestyHD.exe: would update existing .mpst section data at file offset 0x{0:X}." -f $patchSectionRawOffset)
    }
    if (-not $saveAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch mod-save hook at file offset 0x{0:X}." -f $SaveCallOffset)
    }
    if (-not $loadAlreadyPatched) {
        Write-Host ("MajestyHD.exe: would patch mod-load hook at file offset 0x{0:X}." -f $LoadCallOffset)
    }
    return
}

Assert-FileWritable $exePath

if (-not (Test-Path -LiteralPath $preferenceDir)) {
    New-Item -ItemType Directory -Path $preferenceDir | Out-Null
}
# Carry across a list saved by an older build that wrote into the game folder.
if (
    (-not (Test-Path -LiteralPath $preferencePath)) -and
    (Test-Path -LiteralPath $legacyPreferencePath)
) {
    Copy-Item -LiteralPath $legacyPreferencePath -Destination $preferencePath
}

Save-PreInstallBackup $exePath $backupDir $backupPath "Remember Active Mods"

$targetLength = if ($existingSection) { $bytes.Length } else { $patchedFileSize }
$patchedBytes = New-Object byte[] $targetLength
[Array]::Copy($bytes, 0, $patchedBytes, 0, $bytes.Length)

if (-not $existingSection) {
    [BitConverter]::GetBytes([uint16]($pe.SectionCount + 1)).CopyTo($patchedBytes, $pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$newSizeOfImage).CopyTo($patchedBytes, $pe.SizeOfImageOffset)
}
Write-Bytes $patchedBytes $patchSectionHeaderOffset $PatchSectionHeader
Write-Bytes $patchedBytes $SaveCallOffset $PatchedSaveCall
Write-Bytes $patchedBytes $LoadCallOffset $PatchedLoadCall
Write-Bytes $patchedBytes $patchSectionRawOffset $patchBlob

[IO.File]::WriteAllBytes($exePath, $patchedBytes)

Write-Host "Done. Majesty should now remember the mods in the Active list across launches."
Write-Host "Use Uninstall - Restore Stock Mod Selection.bat to restore stock behavior."
