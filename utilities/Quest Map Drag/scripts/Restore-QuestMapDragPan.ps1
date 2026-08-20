param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DefaultGamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD"

function Get-QuestMapDragProfiles {
    return @(
        [pscustomobject]@{
            Id = "public"
            DisplayName = "Default Public (1.5.2.24)"
            BuildSignatureOffset = 0x795D0
            BuildSignatureBytes = [byte[]]@(0x6A,0xFF,0x68,0xC8,0xD1,0x6E,0x00,0x64,0xA1,0x00,0x00,0x00,0x00,0x50,0x83,0xEC,0x24,0x53,0x55,0x56,0x57)
            HookOffset = 0x79FB5
            CaveOffset = 0x334280
            OriginalHookBytes = [byte[]]@(0x8B,0x44,0x24,0x40,0x8B,0x4C,0x24,0x20)
            HookBytes = [byte[]]@(0xE9,0xC6,0xA2,0x2B,0x00,0x90,0x90,0x90)
            StubBytes = [Convert]::FromBase64String(
                "YGoB/xV8VHMAZqkAgA+EiwAAAIt0JAxo7CV8AGjoJXwA6MoE8P+DxAih6CV8ADtGdHxrO0Z8f2ah7CV8ADtGeHxcO4aAAAAAf1SBPeAlfABEUkFHdRyh5CV8ACsF6CV8AAFGQKHwJXwAKwXsJXwAAUYgoeglfACj5CV8AKHsJXwAo/AlfADHBeAlfABEUkFHYYtEJECLTCQg6Z9c1P/HBeAlfAAAAAAA6+Y="
            )
        },
        [pscustomobject]@{
            Id = "beta2"
            DisplayName = "beta2 Steam Multiplayer Support (1.5.2.28)"
            BuildSignatureOffset = 0x77D80
            BuildSignatureBytes = [byte[]]@(0x6A,0xFF,0x68,0x98,0x26,0x70,0x00,0x64,0xA1,0x00,0x00,0x00,0x00,0x50,0x83,0xEC,0x24,0x53,0x55,0x56,0x57)
            HookOffset = 0x7878D
            CaveOffset = 0x34C610
            OriginalHookBytes = [byte[]]@(0x8B,0x44,0x24,0x48,0x8B,0x54,0x24,0x24)
            HookBytes = [byte[]]@(0xE9,0x7E,0x3E,0x2D,0x00,0x90,0x90,0x90)
            StubBytes = [Convert]::FromBase64String(
                "YGoB/xU45XQAZqkAgA+EjgAAAIt0JAxoXBF+AGhYEX4A6HrV7/+DxAihWBF+ADtGeHxuO4aAAAAAf2ahXBF+ADtGfHxcO4aEAAAAf1SBPVARfgBEUkFHdRyhVBF+ACsFWBF+AAFGSKFgEX4AKwVcEX4AAUYkoVgRfgCjVBF+AKFcEX4Ao2ARfgDHBVARfgBEUkFHYYtEJEiLVCQk6eTA0v/HBVARfgAAAAAA6+Y="
            )
        }
    )
}

function Get-MajestyBuildProfile {
    param([byte[]]$Bytes)
    $matches = @(Get-QuestMapDragProfiles | Where-Object {
        Test-BytesEqual $Bytes $_.BuildSignatureOffset $_.BuildSignatureBytes
    })
    if ($matches.Count -ne 1) {
        throw "MajestyHD.exe is not a supported stock Steam build. Supported builds: Default Public 1.5.2.24 and beta2 1.5.2.28."
    }
    return $matches[0]
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

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$profile = Get-MajestyBuildProfile $bytes
$HookOffset = [int]$profile.HookOffset
$CaveOffset = [int]$profile.CaveOffset
[byte[]]$OriginalHookBytes = $profile.OriginalHookBytes
[byte[]]$HookBytes = $profile.HookBytes
[byte[]]$StubBytes = $profile.StubBytes
$hookIsPatched = Test-BytesEqual $bytes $HookOffset $HookBytes
$hookIsStock = Test-BytesEqual $bytes $HookOffset $OriginalHookBytes
$stubIsPatched = Test-BytesEqual $bytes $CaveOffset $StubBytes

Write-Host "Majesty Gold HD Quest Map Drag restore"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Game build: $($profile.DisplayName)"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($hookIsStock -and -not $stubIsPatched) {
    Write-Host "MajestyHD.exe: click-drag panning is not installed."
    return
}

if (-not $hookIsPatched) {
    throw ("MajestyHD.exe does not contain this click-drag hook at file offset 0x{0:X}. Refusing to restore." -f $HookOffset)
}
if (-not $stubIsPatched) {
    throw ("MajestyHD.exe does not contain this click-drag stub at file offset 0x{0:X}. Refusing to restore." -f $CaveOffset)
}

if ($DryRun) {
    Write-Host ("MajestyHD.exe: would restore hook at file offset 0x{0:X}." -f $HookOffset)
    Write-Host ("MajestyHD.exe: would clear click-drag stub at file offset 0x{0:X}." -f $CaveOffset)
    return
}

Assert-FileWritable $exePath

for ($i = 0; $i -lt $OriginalHookBytes.Length; $i++) {
    $bytes[$HookOffset + $i] = $OriginalHookBytes[$i]
}
for ($i = 0; $i -lt $StubBytes.Length; $i++) {
    $bytes[$CaveOffset + $i] = 0
}

[IO.File]::WriteAllBytes($exePath, $bytes)

Write-Host "Done. Click-drag quest map panning has been removed."
