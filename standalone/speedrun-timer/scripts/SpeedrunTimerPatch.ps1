$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$SectionName = ".msrt"
$PatchRawSize = 0x2000
$PatchVirtualSize = 0x2000
$BackupDirName = "_speedrun_timer_originals"

# PE section characteristics: code, execute, read, write. The section holds runtime scratch state.
$SectionCharacteristics = 3758096416  # 0xE0000020: code, execute, read, write
$BackupName = "MajestyHD.exe.before-speedrun-timer"

$ImageBase = 0x400000
$SpeedGlobal = 0x7B5304
$QueryPerformanceFrequencyIat = 0x7351BC
$QueryPerformanceCounterIat = 0x7351C0
$GetTickCountIat = 0x735178
$TimeGetTimeIat = 0x7355C8
$GetProcAddressIat = 0x735190
$LoadLibraryAIat = 0x735194
$GetActiveWindowIat = 0x7354AC

$StartHookVa = 0x4D9B50
$StartHookOffset = 0xD8F50
$StartOriginal = [byte[]]@(0xC7,0x44,0x24,0x34,0xFF,0xFF,0xFF,0xFF)

$VictoryHookVa = 0x42F250
$VictoryHookOffset = 0x2E650
$VictoryOriginal = [byte[]]@(0x83,0xEC,0x24,0x56,0x8B,0x74,0x24,0x2C)

$LossHookVa = 0x42F3D0
$LossHookOffset = 0x2E7D0
$LossOriginal = [byte[]]@(0x83,0xEC,0x20,0x56,0x8B,0x74,0x24,0x28)

$QpcOriginal = [byte[]]@(0xFF,0x15,0xC0,0x51,0x73,0x00)
$QpcCalls = @(
    @(0x42666B, 0x25A6B), @(0x426967, 0x25D67), @(0x426A84, 0x25E84), @(0x552C94, 0x152094),
    @(0x55316F, 0x15256F), @(0x553222, 0x152622), @(0x5532B8, 0x1526B8), @(0x5533C6, 0x1527C6),
    @(0x553480, 0x152880), @(0x553560, 0x152960), @(0x55361A, 0x152A1A), @(0x553713, 0x152B13),
    @(0x553866, 0x152C66), @(0x6D9DED, 0x2D91ED)
)

$GetTickCountOriginal = [byte[]]@(0xFF,0x15,0x78,0x51,0x73,0x00)
$GetTickCountCalls = @(
    @(0x58C3F8, 0x18B7F8), @(0x58C454, 0x18B854), @(0x591C90, 0x191090),
    @(0x5927E4, 0x191BE4), @(0x6D9DE1, 0x2D91E1)
)

$TimeGetTimeOriginal = [byte[]]@(0xFF,0x15,0xC8,0x55,0x73,0x00)
$TimeGetTimeCalls = @(
    @(0x426A05,0x25E05), @(0x428E6F,0x2826F), @(0x455F75,0x55375), @(0x45E677,0x5DA77),
    @(0x466E0C,0x6620C), @(0x4683F4,0x677F4), @(0x468518,0x67918), @(0x46854C,0x6794C),
    @(0x46EAE7,0x6DEE7), @(0x46F12F,0x6E52F), @(0x47F6CC,0x7EACC), @(0x485801,0x84C01),
    @(0x4C8EE5,0xC82E5), @(0x4D2D46,0xD2146), @(0x4D3057,0xD2457), @(0x4D3164,0xD2564),
    @(0x4D31E0,0xD25E0), @(0x4D3349,0xD2749), @(0x4D37C8,0xD2BC8), @(0x4D3863,0xD2C63),
    @(0x4D3964,0xD2D64), @(0x4D4685,0xD3A85), @(0x4E24EB,0xE18EB), @(0x4F53A0,0xF47A0),
    @(0x50C365,0x10B765), @(0x594C21,0x194021), @(0x597883,0x196C83), @(0x59CB3E,0x19BF3E),
    @(0x59CCAF,0x19C0AF), @(0x5BABF9,0x1B9FF9), @(0x6022A3,0x2016A3), @(0x6022D3,0x2016D3),
    @(0x602702,0x201B02), @(0x602762,0x201B62), @(0x607203,0x206603), @(0x607213,0x206613),
    @(0x607233,0x206633), @(0x6170E7,0x2164E7), @(0x6263B1,0x2257B1), @(0x6305F1,0x22F9F1),
    @(0x63062F,0x22FA2F), @(0x635010,0x234410), @(0x635050,0x234450), @(0x635080,0x234480),
    @(0x6350B0,0x2344B0), @(0x63A72A,0x239B2A), @(0x63BD90,0x23B190), @(0x63BE21,0x23B221),
    @(0x63FD82,0x23F182), @(0x67C5EE,0x27B9EE), @(0x67C635,0x27BA35), @(0x67C6D5,0x27BAD5),
    @(0x67D025,0x27C425), @(0x67D668,0x27CA68), @(0x686473,0x285873), @(0x690409,0x28F809),
    @(0x69FB70,0x29EF70), @(0x69FD46,0x29F146), @(0x6A5F2D,0x2A532D), @(0x6B66BD,0x2B5ABD),
    @(0x6BC3DF,0x2BB7DF), @(0x6BC41C,0x2BB81C), @(0x6C0740,0x2BFB40), @(0x6CE844,0x2CDC44),
    @(0x6CE959,0x2CDD59), @(0x6CEA25,0x2CDE25), @(0x6CEC6E,0x2CE06E), @(0x6CFA0D,0x2CEE0D),
    @(0x6CFC84,0x2CF084)
)

# Quest-start trigger.
#
# The timer starts on Majesty's new-quest game-speed object init at VA 0x429006
# and 0x429019. Both sites hold the same 6-byte instruction, and both continue
# at site + 6. There are two ways to get control there:
#
#   Bridge mode - Remember Game Speed (.mskp) already owns both sites. Its two
#                 object-init blocks sit at .mskp blob offsets 0x400 and 0x440
#                 and end with a jump back to the game at blob +0x29. We
#                 redirect those two tail jumps into our own stubs.
#
#   Direct mode - .mskp is absent, so we hook the two .text sites ourselves.
#                 Our stub must replay the displaced instruction, because there
#                 is no Remember Game Speed block ahead of us to have done it.
#
# The two modes are mutually exclusive: if .mskp is installed it already owns
# the .text sites, so direct mode can never collide with it.
#
# Section placement is resolved from the PE section table at install time. Do
# not hardcode .mskp addresses here; they depend on the user's install order.
$MskpSectionName = ".mskp"

# mov [eax+0x98], esi
$SpeedObjectInitOriginal = [byte[]]@(0x89,0xB0,0x98,0x00,0x00,0x00)

$DirectStartHooks = @(
    @{ Va = 0x429006; Offset = 0x28406; ReturnVa = 0x42900C; BlobTarget = 0x140 },
    @{ Va = 0x429019; Offset = 0x28419; ReturnVa = 0x42901F; BlobTarget = 0x160 }
)

$MskpBridgeSites = @(
    @{ BlobOffset = 0x429; ReturnVa = 0x42900C; BlobTarget = 0x100 },
    @{ BlobOffset = 0x469; ReturnVa = 0x42901F; BlobTarget = 0x130 }
)

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

function New-RelativeCallBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE8
    [BitConverter]::GetBytes($relative).CopyTo($result, 1)
    return $result
}

function New-RelativeJumpBytes {
    param([uint32]$SourceVa, [uint32]$TargetVa)

    $relative = [int]([int64]$TargetVa - ([int64]$SourceVa + 5))
    $result = New-Object byte[] 5
    $result[0] = 0xE9
    [BitConverter]::GetBytes($relative).CopyTo($result, 1)
    return $result
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

function New-SpeedrunPatchBlob {
    param([uint32]$PatchVa)

    $script:CodePatchVa = $PatchVa
    $script:CodeBytes = New-Object byte[] $PatchRawSize
    $script:CodeOffset = 0
    $script:CodeLabels = @{}
    $script:CodePatches = New-Object System.Collections.ArrayList

    function Code-Va { return [uint32]($script:CodePatchVa + $script:CodeOffset) }
    function Code-Label { param([string]$Name) $script:CodeLabels[$Name] = $script:CodeOffset }
    function Code-Seek { param([int]$Offset) $script:CodeOffset = $Offset }
    function Code-Byte {
        param([Parameter(ValueFromRemainingArguments=$true)][int[]]$Values)
        foreach ($value in $Values) {
            $script:CodeBytes[$script:CodeOffset] = [byte]($value -band 0xFF)
            $script:CodeOffset++
        }
    }
    function Code-Raw {
        param([byte[]]$Values)
        for ($i = 0; $i -lt $Values.Length; $i++) {
            $script:CodeBytes[$script:CodeOffset + $i] = $Values[$i]
        }
        $script:CodeOffset += $Values.Length
    }
    function Code-U32 {
        param([uint32]$Value)
        Code-Raw ([BitConverter]::GetBytes($Value))
    }
    function Code-IatCall {
        param([uint32]$IatVa)
        Code-Byte 0xFF 0x15
        Code-U32 $IatVa
    }
    function Code-Call {
        param([string]$Label)
        $patchAt = $script:CodeOffset
        Code-Byte 0xE8 0 0 0 0
        [void]$script:CodePatches.Add([pscustomobject]@{ Offset = $patchAt + 1; Label = $Label; NextVa = $script:CodePatchVa + $patchAt + 5; Kind = "rel32" })
    }
    function Code-Jmp {
        param([string]$Label)
        $patchAt = $script:CodeOffset
        Code-Byte 0xE9 0 0 0 0
        [void]$script:CodePatches.Add([pscustomobject]@{ Offset = $patchAt + 1; Label = $Label; NextVa = $script:CodePatchVa + $patchAt + 5; Kind = "rel32" })
    }
    function Code-Je32 {
        param([string]$Label)
        $patchAt = $script:CodeOffset
        Code-Byte 0x0F 0x84 0 0 0 0
        [void]$script:CodePatches.Add([pscustomobject]@{ Offset = $patchAt + 2; Label = $Label; NextVa = $script:CodePatchVa + $patchAt + 6; Kind = "rel32" })
    }
    function Code-Jb8 {
        param([string]$Label)
        $patchAt = $script:CodeOffset
        Code-Byte 0x72 0
        [void]$script:CodePatches.Add([pscustomobject]@{ Offset = $patchAt + 1; Label = $Label; NextVa = $script:CodePatchVa + $patchAt + 2; Kind = "rel8" })
    }

    function Mov-AbsU8 { param([uint32]$Address, [byte]$Value) Code-Byte 0xC6 0x05; Code-U32 $Address; Code-Byte $Value }
    function Mov-AbsU32 { param([uint32]$Address, [uint32]$Value) Code-Byte 0xC7 0x05; Code-U32 $Address; Code-U32 $Value }
    function Mov-EaxAbs { param([uint32]$Address) Code-Byte 0xA1; Code-U32 $Address }
    function Mov-AbsEax { param([uint32]$Address) Code-Byte 0xA3; Code-U32 $Address }
    function Mov-AbsEdx { param([uint32]$Address) Code-Byte 0x89 0x15; Code-U32 $Address }
    function Mov-MemAl { param([uint32]$Address) Code-Byte 0xA2; Code-U32 $Address }
    function Mov-MemDl { param([uint32]$Address) Code-Byte 0x88 0x15; Code-U32 $Address }
    function Write-TwoDigits {
        param([uint32]$Address)
        Code-Byte 0x31 0xD2
        Code-Byte 0xB9; Code-U32 10
        Code-Byte 0xF7 0xF1
        Code-Byte 0x04 0x30
        Code-Byte 0x80 0xC2 0x30
        Mov-MemAl $Address
        Mov-MemDl ([uint32]($Address + 1))
    }

    $running = $PatchVa + 0x1000
    $showResult = $PatchVa + 0x1001
    $lastCounter = $PatchVa + 0x1004
    $lastStatus = $PatchVa + 0x100C
    $adjustedMs = $PatchVa + 0x1010
    $finalMs = $PatchVa + 0x1014
    $displayMs = $PatchVa + 0x1018
    $qpcRemainder = $PatchVa + 0x101C
    $qpcFrequency = $PatchVa + 0x1020
    $currentCounter = $PatchVa + 0x1024
    $setWindowTextAPtr = $PatchVa + 0x102C
    $tempMs = $PatchVa + 0x1030
    $tempSec = $PatchVa + 0x1034
    $qpcDelta = $PatchVa + 0x1038
    $statusBuffer = $PatchVa + 0x1040
    $user32Name = $PatchVa + 0x10A0
    $setWindowTextName = $PatchVa + 0x10AC

    Code-Label "tick_wrapper"
    Code-IatCall $GetTickCountIat
    Code-Byte 0x50 0x60
    Code-Call "update_and_emit"
    Code-Byte 0x61 0x58 0xC3

    Code-Seek 0x40
    Code-Label "time_wrapper"
    Code-IatCall $TimeGetTimeIat
    Code-Byte 0x50 0x60
    Code-Call "update_and_emit"
    Code-Byte 0x61 0x58 0xC3

    Code-Seek 0x100
    Code-Label "mskp_start_one"
    Code-Byte 0x60
    Code-Call "timer_start"
    Code-Byte 0x61
    Code-Raw (New-RelativeJumpBytes (Code-Va) 0x42900C)

    Code-Seek 0x130
    Code-Label "mskp_start_two"
    Code-Byte 0x60
    Code-Call "timer_start"
    Code-Byte 0x61
    Code-Raw (New-RelativeJumpBytes (Code-Va) 0x42901F)

    # Direct quest-start stubs, used only when Remember Game Speed is absent.
    # Unlike the bridge stubs above, these own the .text site outright, so they
    # replay the displaced instruction before returning. Same shape as the
    # victory and loss hooks below. 18 bytes each; 0x180 is the next block.
    Code-Seek 0x140
    Code-Label "direct_start_one"
    Code-Byte 0x60
    Code-Call "timer_start"
    Code-Byte 0x61
    Code-Raw $SpeedObjectInitOriginal
    Code-Raw (New-RelativeJumpBytes (Code-Va) 0x42900C)

    Code-Seek 0x160
    Code-Label "direct_start_two"
    Code-Byte 0x60
    Code-Call "timer_start"
    Code-Byte 0x61
    Code-Raw $SpeedObjectInitOriginal
    Code-Raw (New-RelativeJumpBytes (Code-Va) 0x42901F)

    Code-Seek 0x180
    Code-Label "victory_hook"
    Code-Byte 0x60
    Code-Call "timer_stop"
    Code-Byte 0x61
    Code-Raw $VictoryOriginal
    Code-Raw (New-RelativeJumpBytes (Code-Va) ([uint32]($VictoryHookVa + $VictoryOriginal.Length)))

    Code-Seek 0x1C0
    Code-Label "loss_hook"
    Code-Byte 0x60
    Code-Call "timer_stop"
    Code-Byte 0x61
    Code-Raw $LossOriginal
    Code-Raw (New-RelativeJumpBytes (Code-Va) ([uint32]($LossHookVa + $LossOriginal.Length)))

    Code-Seek 0x240
    Code-Label "timer_start"
    Mov-AbsU8 $running 1
    Mov-AbsU8 $showResult 0
    Mov-AbsU32 $adjustedMs 0
    Mov-AbsU32 $finalMs 0
    Mov-AbsU32 $displayMs 0
    Mov-AbsU32 $qpcRemainder 0
    Code-Byte 0x68; Code-U32 $qpcFrequency
    Code-IatCall $QueryPerformanceFrequencyIat
    Code-Byte 0x85 0xC0
    Code-Je32 "timer_start_done"
    Code-Byte 0x68; Code-U32 $lastCounter
    Code-IatCall $QueryPerformanceCounterIat
    Code-Byte 0x85 0xC0
    Code-Je32 "timer_start_done"
    Code-IatCall $GetTickCountIat
    Mov-AbsEax $lastStatus
    Code-Call "format_time"
    Code-Call "emit_status"
    Code-Label "timer_start_done"
    Code-Byte 0xC3

    Code-Seek 0x2C0
    Code-Label "timer_stop"
    Code-Byte 0x80 0x3D; Code-U32 $running; Code-Byte 0
    Code-Je32 "timer_stop_done"
    Code-Call "update_and_emit"
    Mov-AbsU8 $running 0
    Mov-AbsU8 $showResult 1
    Mov-EaxAbs $adjustedMs
    Mov-AbsEax $finalMs
    Mov-AbsEax $displayMs
    Code-Call "format_time"
    Code-Call "emit_status"
    Code-Label "timer_stop_done"
    Code-Byte 0xC3

    Code-Seek 0x380
    Code-Label "update_and_emit"
    Code-Byte 0x80 0x3D; Code-U32 $running; Code-Byte 0
    Code-Je32 "update_done"
    Code-Byte 0x68; Code-U32 $currentCounter
    Code-IatCall $QueryPerformanceCounterIat
    Code-Byte 0x85 0xC0
    Code-Je32 "update_done"
    Mov-EaxAbs $currentCounter
    Code-Byte 0x2B 0x05; Code-U32 $lastCounter
    Mov-AbsEax $qpcDelta
    Mov-EaxAbs $currentCounter
    Mov-AbsEax $lastCounter
    Mov-EaxAbs ([uint32]($currentCounter + 4))
    Mov-AbsEax ([uint32]($lastCounter + 4))
    Mov-EaxAbs $qpcDelta
    Code-Byte 0x85 0xC0
    Code-Je32 "update_maybe_emit"
    Code-Byte 0xBB; Code-U32 50
    Code-Byte 0xF7 0xE3
    Code-Byte 0x8B 0x0D; Code-U32 $SpeedGlobal
    Code-Byte 0x85 0xC9
    Code-Je32 "update_done"
    Code-Byte 0xF7 0xF1
    Code-Byte 0xB9; Code-U32 1000
    Code-Byte 0xF7 0xE1
    Code-Byte 0x03 0x05; Code-U32 $qpcRemainder
    Code-Byte 0x83 0xD2 0x00
    Code-Byte 0x8B 0x0D; Code-U32 $qpcFrequency
    Code-Byte 0x85 0xC9
    Code-Je32 "update_done"
    Code-Byte 0xF7 0xF1
    Mov-AbsEdx $qpcRemainder
    Code-Byte 0x01 0x05; Code-U32 $adjustedMs
    Code-Label "update_maybe_emit"
    Mov-EaxAbs $adjustedMs
    Mov-AbsEax $displayMs
    Code-IatCall $GetTickCountIat
    Code-Byte 0x89 0xC6
    Code-Byte 0x2B 0x05; Code-U32 $lastStatus
    Code-Byte 0x3D; Code-U32 1000
    Code-Jb8 "update_done"
    Code-Byte 0x89 0x35; Code-U32 $lastStatus
    Code-Call "format_time"
    Code-Call "emit_status"
    Code-Label "update_done"
    Code-Byte 0xC3

    Code-Seek 0x480
    Code-Label "emit_status"
    Code-Byte 0x83 0x3D; Code-U32 $setWindowTextAPtr; Code-Byte 0
    Code-Je32 "resolve_title_proc"
    Code-Jmp "have_title_proc"
    Code-Label "resolve_title_proc"
    Code-Byte 0x68; Code-U32 $user32Name
    Code-IatCall $LoadLibraryAIat
    Code-Byte 0x85 0xC0
    Code-Je32 "emit_done"
    Code-Byte 0x68; Code-U32 $setWindowTextName
    Code-Byte 0x50
    Code-IatCall $GetProcAddressIat
    Code-Byte 0x85 0xC0
    Code-Je32 "emit_done"
    Mov-AbsEax $setWindowTextAPtr
    Code-Label "have_title_proc"
    Code-IatCall $GetActiveWindowIat
    Code-Byte 0x85 0xC0
    Code-Je32 "emit_done"
    Code-Byte 0x68; Code-U32 $statusBuffer
    Code-Byte 0x50
    Code-Byte 0xFF 0x15; Code-U32 $setWindowTextAPtr
    Code-Label "emit_done"
    Code-Byte 0xC3

    Code-Seek 0x600
    Code-Label "format_time"
    Mov-EaxAbs $displayMs
    Code-Byte 0x31 0xD2
    Code-Byte 0xB9; Code-U32 1000
    Code-Byte 0xF7 0xF1
    Mov-AbsEdx $tempMs
    Code-Byte 0x31 0xD2
    Code-Byte 0xB9; Code-U32 60
    Code-Byte 0xF7 0xF1
    Mov-AbsEdx $tempSec
    Code-Byte 0x31 0xD2
    Code-Byte 0xB9; Code-U32 100
    Code-Byte 0xF7 0xF1
    Code-Byte 0x89 0xD0
    Write-TwoDigits ([uint32]($statusBuffer + 25))
    Mov-EaxAbs $tempSec
    Write-TwoDigits ([uint32]($statusBuffer + 28))
    Mov-EaxAbs $tempMs
    Code-Byte 0x31 0xD2
    Code-Byte 0xB9; Code-U32 100
    Code-Byte 0xF7 0xF1
    Code-Byte 0x04 0x30
    Mov-MemAl ([uint32]($statusBuffer + 31))
    Code-Byte 0x89 0xD0
    Write-TwoDigits ([uint32]($statusBuffer + 32))
    Code-Byte 0xC3

    Code-Seek 0x1040
    Code-Raw ([Text.Encoding]::ASCII.GetBytes("Majesty - Speedrun Time: 00:00.000`0"))
    Code-Seek 0x10A0
    Code-Raw ([Text.Encoding]::ASCII.GetBytes("user32.dll`0"))
    Code-Seek 0x10AC
    Code-Raw ([Text.Encoding]::ASCII.GetBytes("SetWindowTextA`0"))

    foreach ($patch in $script:CodePatches) {
        $targetVa = [int64]($script:CodePatchVa + $script:CodeLabels[$patch.Label])
        $delta = [int64]($targetVa - $patch.NextVa)
        if ($patch.Kind -eq "rel32") {
            [BitConverter]::GetBytes([int]$delta).CopyTo($script:CodeBytes, $patch.Offset)
        } elseif ($patch.Kind -eq "rel8") {
            if ($delta -lt -128 -or $delta -gt 127) {
                throw "rel8 jump to $($patch.Label) is out of range."
            }
            $script:CodeBytes[$patch.Offset] = [byte]([sbyte]$delta)
        } else {
            throw "Unknown patch kind $($patch.Kind)."
        }
    }

    return $script:CodeBytes
}

function Get-SpeedrunPatchLayout {
    param([byte[]]$Bytes)

    $pe = Get-PeInfo $Bytes
    $existing = $pe.Sections | Where-Object { $_.Name -eq $SectionName } | Select-Object -First 1

    if ($existing) {
        $patchRaw = [uint32]$existing.RawOffset
        $patchRva = [uint32]$existing.Rva
        $patchVa = [uint32]($ImageBase + $patchRva)
        $patchHeaderOffset = [int]$existing.HeaderOffset
        $patchedFileSize = [int]($patchRaw + $PatchRawSize)
    } else {
        $last = $pe.Sections | Sort-Object RawOffset | Select-Object -Last 1
        $patchRaw = Align-Value ([uint32]$Bytes.Length) ([uint32]$pe.FileAlignment)
        $lastVirtualEnd = [uint32]($last.Rva + [Math]::Max($last.VirtualSize, $last.RawSize))
        $patchRva = Align-Value $lastVirtualEnd ([uint32]$pe.SectionAlignment)
        $patchVa = [uint32]($ImageBase + $patchRva)
        $patchHeaderOffset = [int]($pe.SectionTableOffset + ($pe.SectionCount * 40))
        $patchedFileSize = [int]($patchRaw + $PatchRawSize)
        if (($patchHeaderOffset + 40) -gt $pe.SizeOfHeaders) {
            throw "No room remains in the PE header for another patch section."
        }
        if (-not (Test-ZeroRange $Bytes $patchHeaderOffset 40)) {
            throw ("PE header slot at 0x{0:X} is not empty." -f $patchHeaderOffset)
        }
        if ($patchRaw -ne $Bytes.Length) {
            throw ("MajestyHD.exe has unaligned trailing data. Expected 0x{0:X}, got 0x{1:X}." -f $patchRaw, $Bytes.Length)
        }
    }

    $header = New-SectionHeader $SectionName $PatchVirtualSize $patchRva $PatchRawSize $patchRaw
    $blob = New-SpeedrunPatchBlob $patchVa
    $newSizeOfImage = Align-Value ([uint32]($patchRva + $PatchVirtualSize)) ([uint32]$pe.SectionAlignment)

    return [pscustomobject]@{
        Pe = $pe
        Existing = $existing
        PatchRaw = $patchRaw
        PatchRva = $patchRva
        PatchVa = $patchVa
        PatchHeaderOffset = $patchHeaderOffset
        PatchedFileSize = $patchedFileSize
        Header = $header
        Blob = $blob
        NewSizeOfImage = $newSizeOfImage
    }
}

function Get-QuestStartPatches {
    param([uint32]$PatchVa, $Pe)

    $mskp = $null
    if ($Pe) {
        $mskp = $Pe.Sections | Where-Object { $_.Name -eq $MskpSectionName } | Select-Object -First 1
    }

    if ($mskp) {
        $mskpVa = [uint32]($ImageBase + $mskp.Rva)
        $patches = foreach ($site in $MskpBridgeSites) {
            $siteVa = [uint32]($mskpVa + $site.BlobOffset)
            [pscustomobject]@{
                Name     = "Remember Game Speed bridge"
                Va       = $siteVa
                Offset   = [int]($mskp.RawOffset + $site.BlobOffset)
                Original = New-RelativeJumpBytes $siteVa ([uint32]$site.ReturnVa)
                Patched  = New-RelativeJumpBytes $siteVa ([uint32]($PatchVa + $site.BlobTarget))
            }
        }
        return [pscustomobject]@{ Mode = "bridge"; Patches = @($patches) }
    }

    $patches = foreach ($site in $DirectStartHooks) {
        [pscustomobject]@{
            Name     = "quest-start hook"
            Va       = [uint32]$site.Va
            Offset   = [int]$site.Offset
            Original = $SpeedObjectInitOriginal
            Patched  = (New-RelativeJumpBytes ([uint32]$site.Va) ([uint32]($PatchVa + $site.BlobTarget))) + [byte[]]@(0x90)
        }
    }
    return [pscustomobject]@{ Mode = "direct"; Patches = @($patches) }
}

function New-SpeedrunPatchSets {
    param([uint32]$PatchVa, $Pe)

    $startPatch = (New-RelativeJumpBytes $StartHookVa ([uint32]($PatchVa + 0x100))) + [byte[]]@(0x90,0x90,0x90)
    $oldVictoryPatch = (New-RelativeJumpBytes $VictoryHookVa ([uint32]($PatchVa + 0x140))) + [byte[]]@(0x90,0x90,0x90)
    $oldLossPatch = (New-RelativeJumpBytes $LossHookVa ([uint32]($PatchVa + 0x180))) + [byte[]]@(0x90,0x90,0x90)
    $victoryPatch = (New-RelativeJumpBytes $VictoryHookVa ([uint32]($PatchVa + 0x180))) + [byte[]]@(0x90,0x90,0x90)
    $lossPatch = (New-RelativeJumpBytes $LossHookVa ([uint32]($PatchVa + 0x1C0))) + [byte[]]@(0x90,0x90,0x90)

    $hooks = @(
        [pscustomobject]@{ Name = "victory hook"; Offset = $VictoryHookOffset; Original = $VictoryOriginal; Patched = $victoryPatch; OldPatches = @($oldVictoryPatch) },
        [pscustomobject]@{ Name = "loss hook"; Offset = $LossHookOffset; Original = $LossOriginal; Patched = $lossPatch; OldPatches = @($oldLossPatch) }
    )
    $legacyQpcPatches = foreach ($entry in $QpcCalls) {
        [pscustomobject]@{ Va = [uint32]$entry[0]; Offset = [int]$entry[1]; Patched = (New-RelativeCallBytes ([uint32]$entry[0]) $PatchVa) + [byte[]]@(0x90) }
    }
    $tickPatches = foreach ($entry in $GetTickCountCalls) {
        [pscustomobject]@{ Va = [uint32]$entry[0]; Offset = [int]$entry[1]; Patched = (New-RelativeCallBytes ([uint32]$entry[0]) $PatchVa) + [byte[]]@(0x90) }
    }
    $timePatches = foreach ($entry in $TimeGetTimeCalls) {
        [pscustomobject]@{ Va = [uint32]$entry[0]; Offset = [int]$entry[1]; Patched = (New-RelativeCallBytes ([uint32]$entry[0]) ([uint32]($PatchVa + 0x40))) + [byte[]]@(0x90) }
    }
    $questStart = Get-QuestStartPatches $PatchVa $Pe

    return [pscustomobject]@{
        StartPatch = $startPatch
        Hooks = $hooks
        LegacyQpcPatches = $legacyQpcPatches
        TickPatches = $tickPatches
        TimePatches = $timePatches
        QuestStartMode = $questStart.Mode
        QuestStartPatches = $questStart.Patches
    }
}
