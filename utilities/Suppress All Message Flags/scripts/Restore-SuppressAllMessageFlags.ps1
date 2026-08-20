param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
[byte[]]$OriginalBytes = @(0x8B, 0x4C, 0x24, 0x10, 0x56, 0x57)
[byte[]]$PatchedBytes = @(0xC3, 0x90, 0x90, 0x90, 0x90, 0x90)
[byte[]]$ConstructorTail = @(0x8B, 0x7C, 0x24, 0x0C, 0x6A, 0x00, 0x6A, 0xFF, 0x83, 0xEC)

$BuildProfiles = @(
    [pscustomobject]@{
        Id = "public-1.5.2.24"
        DisplayName = "Default Public Version (1.5.2.24)"
        FileVersion = "1.5.2.24"
        TimeDateStamp = [uint32]0x5897B72F
        MinimumLength = 3933696
        SectionHeaderSha256 = "1C1832EEBAB0168B460E237D41CCDFC7552B7E74CCA4ADF41336BE357E541F5A"
        PatchOffset = 0x48A90
    },
    [pscustomobject]@{
        Id = "beta2-1.5.2.28"
        DisplayName = "beta2 Steam Multiplayer Support (1.5.2.28)"
        FileVersion = "1.5.2.28"
        TimeDateStamp = [uint32]0x5A8A11D5
        MinimumLength = 4056064
        SectionHeaderSha256 = "0618B6C3CD028E21B21EBE0CCF37BACBFA5A5972503AD83C07CA14D502F12C4A"
        PatchOffset = 0x499A0
    }
)

function Test-BytesEqual {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected)
    if ($Offset -lt 0 -or ($Offset + $Expected.Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Expected[$i]) { return $false }
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
    if (-not (Test-BytesEqual $Bytes ($profile.PatchOffset + $OriginalBytes.Length) $ConstructorTail)) {
        throw ("MajestyHD.exe metadata matches {0}, but the message-flag constructor layout does not. Refusing to guess." -f $profile.DisplayName)
    }
    return $profile
}

function Get-MajestyPath {
    param([string]$RequestedPath)
    if ($RequestedPath) { return $RequestedPath }
    if (Test-Path -LiteralPath $DefaultGamePath) { return $DefaultGamePath }

    $appId = 73230
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
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        $manifest = Join-Path $libraryRoot ("steamapps\appmanifest_" + $appId + ".acf")
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        foreach ($line in Get-Content -LiteralPath $manifest) {
            if ($line -match '"installdir"\s+"([^"]+)"') {
                $named = Join-Path $libraryRoot ("steamapps\common\" + ($Matches[1] -replace '\\\\', '\'))
                if (Test-Path -LiteralPath $named) { return $named }
            }
        }
    }
    throw "Could not find Majesty Gold HD. Re-run with -GamePath."
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
$profile = Get-MajestyBuildProfile $exePath $bytes
$patchOffset = $profile.PatchOffset
$isStock = Test-BytesEqual $bytes $patchOffset $OriginalBytes
$isPatched = Test-BytesEqual $bytes $patchOffset $PatchedBytes

Write-Host "Majesty Gold HD Suppress All Message Flags restore"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Detected build: $($profile.DisplayName)"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($isStock) {
    Write-Host "MajestyHD.exe: stock message-flag behavior is already present."
    return
}
if (-not $isPatched) {
    throw ("MajestyHD.exe does not contain this utility's patch at file offset 0x{0:X}. Refusing to modify unexpected bytes." -f $patchOffset)
}
if ($DryRun) {
    Write-Host ("MajestyHD.exe: would restore the constructor at file offset 0x{0:X}." -f $patchOffset)
    return
}

Assert-FileWritable $exePath
[Array]::Copy($OriginalBytes, 0, $bytes, $patchOffset, $OriginalBytes.Length)
[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host "Done. Stock message icons, sound, and mini-camera focus are restored."
Write-Host "Other Majesty QOL patches were left untouched."
