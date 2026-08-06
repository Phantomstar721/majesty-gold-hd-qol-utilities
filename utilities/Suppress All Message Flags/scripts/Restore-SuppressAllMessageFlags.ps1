param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"
$PatchOffset = 0x48A90

[byte[]]$OriginalBytes = @(0x8B, 0x4C, 0x24, 0x10, 0x56, 0x57)
[byte[]]$PatchedBytes = @(0xC3, 0x90, 0x90, 0x90, 0x90, 0x90)

function Test-BytesEqual {
    param([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected)
    if ($Offset -lt 0 -or ($Offset + $Expected.Length) -gt $Bytes.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Expected[$i]) { return $false }
    }
    return $true
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
$isStock = Test-BytesEqual $bytes $PatchOffset $OriginalBytes
$isPatched = Test-BytesEqual $bytes $PatchOffset $PatchedBytes

Write-Host "Majesty Gold HD Suppress All Message Flags restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($isStock) {
    Write-Host "MajestyHD.exe: stock message-flag behavior is already present."
    return
}
if (-not $isPatched) {
    throw ("MajestyHD.exe does not contain this utility's patch at file offset 0x{0:X}. Refusing to modify unexpected bytes." -f $PatchOffset)
}
if ($DryRun) {
    Write-Host ("MajestyHD.exe: would restore the constructor at file offset 0x{0:X}." -f $PatchOffset)
    return
}

Assert-FileWritable $exePath
[Array]::Copy($OriginalBytes, 0, $bytes, $PatchOffset, $OriginalBytes.Length)
[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host "Done. Stock message icons, sound, and mini-camera focus are restored."
Write-Host "Other Majesty QOL patches were left untouched."

