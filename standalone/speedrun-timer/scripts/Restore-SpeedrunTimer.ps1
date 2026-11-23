param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\SpeedrunTimerPatch.ps1"

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$pe = Get-PeInfo $bytes
$section = $pe.Sections | Where-Object { $_.Name -eq $SectionName } | Select-Object -First 1

Write-Host "Majesty Gold HD Speedrun Timer restore"
Write-Host "Game path: $resolvedGamePath"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if (-not $section) {
    Write-Host "MajestyHD.exe: Speedrun Timer is not installed."
    return
}

$patchVa = [uint32]($ImageBase + $section.Rva)
$patches = New-SpeedrunPatchSets $patchVa $pe

$hookSets = @(
    [pscustomobject]@{ Offset = $StartHookOffset; Original = $StartOriginal; PatchedList = @($patches.StartPatch) },
    [pscustomobject]@{ Offset = $VictoryHookOffset; Original = $VictoryOriginal; PatchedList = @((New-RelativeJumpBytes $VictoryHookVa ([uint32]($patchVa + 0x140))) + [byte[]]@(0x90,0x90,0x90), (New-RelativeJumpBytes $VictoryHookVa ([uint32]($patchVa + 0x180))) + [byte[]]@(0x90,0x90,0x90)) },
    [pscustomobject]@{ Offset = $LossHookOffset; Original = $LossOriginal; PatchedList = @((New-RelativeJumpBytes $LossHookVa ([uint32]($patchVa + 0x180))) + [byte[]]@(0x90,0x90,0x90), (New-RelativeJumpBytes $LossHookVa ([uint32]($patchVa + 0x1C0))) + [byte[]]@(0x90,0x90,0x90)) }
)

$qpcPatches = foreach ($entry in $QpcCalls) {
    [pscustomobject]@{ Offset = [int]$entry[1]; Original = $QpcOriginal; PatchedList = @((New-RelativeCallBytes ([uint32]$entry[0]) $patchVa) + [byte[]]@(0x90)) }
}
$tickPatches = foreach ($entry in $GetTickCountCalls) {
    [pscustomobject]@{ Offset = [int]$entry[1]; Original = $GetTickCountOriginal; PatchedList = @((New-RelativeCallBytes ([uint32]$entry[0]) $patchVa) + [byte[]]@(0x90)) }
}
$timePatches = foreach ($entry in $TimeGetTimeCalls) {
    [pscustomobject]@{ Offset = [int]$entry[1]; Original = $TimeGetTimeOriginal; PatchedList = @((New-RelativeCallBytes ([uint32]$entry[0]) ([uint32]($patchVa + 0x40))) + [byte[]]@(0x90)) }
}
$questStartPatches = foreach ($patch in $patches.QuestStartPatches) {
    [pscustomobject]@{ Offset = $patch.Offset; Original = $patch.Original; PatchedList = @($patch.Patched) }
}

$allChecks = @($hookSets + $qpcPatches + $tickPatches + $timePatches + $questStartPatches)

$anyInstalled = $false
foreach ($check in $allChecks) {
    foreach ($patched in $check.PatchedList) {
        if (Test-BytesEqual $bytes $check.Offset $patched) {
            $anyInstalled = $true
            break
        }
    }
    if ($anyInstalled) { break }
}

if (-not $anyInstalled) {
    Write-Host "MajestyHD.exe: no Speedrun Timer hooks are installed."
    return
}

if ($section.Index -ne ($pe.SectionCount - 1)) {
    throw "$SectionName is not the last section added to MajestyHD.exe, so removing it would break the patches that came after it.

Uninstall in reverse order: whichever utility you installed last must be removed first. Across these tools the section order is .mpst (Remember Active Mods), .mskp (Remember Game Speed), .mczp (Remember Camera Zoom), .msrt (Speedrun Timer), .mfsp (Freestyle Custom CAM Fix) - but only the ones you actually installed will be present.

Run the uninstallers for any utility listed after this one, then run this one again."
}

foreach ($check in $allChecks) {
    $matchesPatched = $false
    foreach ($patched in $check.PatchedList) {
        if (Test-BytesEqual $bytes $check.Offset $patched) {
            $matchesPatched = $true
            break
        }
    }
    if (-not ((Test-BytesEqual $bytes $check.Offset $check.Original) -or $matchesPatched)) {
        throw ("Unexpected bytes at hook file offset 0x{0:X}." -f $check.Offset)
    }
}

$previous = $pe.Sections | Where-Object { $_.Index -eq ($section.Index - 1) } | Select-Object -First 1
$restoredSize = [int]$section.RawOffset
$restoredImageSize = Align-Value ([uint32]($previous.Rva + [Math]::Max($previous.VirtualSize, $previous.RawSize))) ([uint32]$pe.SectionAlignment)

if ($DryRun) {
    Write-Host "Would restore quest-start, victory, loss, status-pulse, and bridge hooks."
    Write-Host ("Would remove {0} section at file offset 0x{1:X}." -f $SectionName, $section.RawOffset)
    return
}

Assert-FileWritable $exePath

$out = New-Object byte[] $restoredSize
[Array]::Copy($bytes, 0, $out, 0, $restoredSize)
foreach ($check in $allChecks) {
    # Only touch sites this install actually patched. Restoring blindly can
    # write past the truncated buffer, and can also stomp a site that a
    # different utility legitimately owns.
    $isPatched = $false
    foreach ($patched in $check.PatchedList) {
        if (Test-BytesEqual $bytes $check.Offset $patched) {
            $isPatched = $true
            break
        }
    }
    if (-not $isPatched) { continue }
    if (($check.Offset + $check.Original.Length) -gt $restoredSize) {
        throw ("Cannot restore hook at file offset 0x{0:X}; it lies outside the truncated image." -f $check.Offset)
    }
    Write-Bytes $out $check.Offset $check.Original
}
[BitConverter]::GetBytes([uint16]($pe.SectionCount - 1)).CopyTo($out, $pe.SectionCountOffset)
[BitConverter]::GetBytes([uint32]$restoredImageSize).CopyTo($out, $pe.SizeOfImageOffset)
Write-Bytes $out $section.HeaderOffset (New-Object byte[] 40)

[IO.File]::WriteAllBytes($exePath, $out)
Write-Host "Done. Speedrun Timer hooks are removed."
