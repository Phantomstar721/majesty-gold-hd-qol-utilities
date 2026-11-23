param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\SpeedrunTimerPatch.ps1"

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$backupDir = Join-Path $resolvedGamePath $BackupDirName
$backupPath = Join-Path $backupDir $BackupName

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Could not find MajestyHD.exe at $exePath."
}

[byte[]]$bytes = [IO.File]::ReadAllBytes($exePath)
$layout = Get-SpeedrunPatchLayout $bytes
$patches = New-SpeedrunPatchSets $layout.PatchVa $layout.Pe

foreach ($hook in $patches.Hooks) {
    $matchesOldPatch = $false
    foreach ($oldPatch in $hook.OldPatches) {
        if (Test-BytesEqual $bytes $hook.Offset $oldPatch) {
            $matchesOldPatch = $true
            break
        }
    }
    if (-not ((Test-BytesEqual $bytes $hook.Offset $hook.Original) -or (Test-BytesEqual $bytes $hook.Offset $hook.Patched) -or $matchesOldPatch)) {
        throw ("Unexpected bytes at {0} file offset 0x{1:X}." -f $hook.Name, $hook.Offset)
    }
}

if (-not ((Test-BytesEqual $bytes $StartHookOffset $StartOriginal) -or (Test-BytesEqual $bytes $StartHookOffset $patches.StartPatch))) {
    throw ("Unexpected bytes at legacy quest-start hook file offset 0x{0:X}." -f $StartHookOffset)
}

foreach ($patch in $patches.LegacyQpcPatches) {
    if (-not ((Test-BytesEqual $bytes $patch.Offset $QpcOriginal) -or (Test-BytesEqual $bytes $patch.Offset $patch.Patched))) {
        throw ("Unexpected bytes at QPC call file offset 0x{0:X} / VA 0x{1:X}." -f $patch.Offset, $patch.Va)
    }
}
foreach ($patch in $patches.TickPatches) {
    if (-not ((Test-BytesEqual $bytes $patch.Offset $GetTickCountOriginal) -or (Test-BytesEqual $bytes $patch.Offset $patch.Patched))) {
        throw ("Unexpected bytes at GetTickCount call file offset 0x{0:X} / VA 0x{1:X}." -f $patch.Offset, $patch.Va)
    }
}
foreach ($patch in $patches.TimePatches) {
    if (-not ((Test-BytesEqual $bytes $patch.Offset $TimeGetTimeOriginal) -or (Test-BytesEqual $bytes $patch.Offset $patch.Patched))) {
        throw ("Unexpected bytes at timeGetTime call file offset 0x{0:X} / VA 0x{1:X}." -f $patch.Offset, $patch.Va)
    }
}
foreach ($patch in $patches.QuestStartPatches) {
    if (-not ((Test-BytesEqual $bytes $patch.Offset $patch.Original) -or (Test-BytesEqual $bytes $patch.Offset $patch.Patched))) {
        throw ("Unexpected bytes at {0} file offset 0x{1:X} / VA 0x{2:X}. Another patch may already own this site." -f $patch.Name, $patch.Offset, $patch.Va)
    }
}

$alreadyInstalled = (
    $layout.Existing -and
    (Test-BytesEqual $bytes $layout.PatchHeaderOffset $layout.Header) -and
    ($bytes.Length -ge $layout.PatchedFileSize) -and
    (Test-BytesEqual $bytes $layout.PatchRaw $layout.Blob) -and
    (Test-BytesEqual $bytes $StartHookOffset $StartOriginal) -and
    (($patches.Hooks | Where-Object { -not (Test-BytesEqual $bytes $_.Offset $_.Patched) }).Count -eq 0) -and
    (($patches.LegacyQpcPatches | Where-Object { -not (Test-BytesEqual $bytes $_.Offset $QpcOriginal) }).Count -eq 0) -and
    (($patches.TickPatches | Where-Object { -not (Test-BytesEqual $bytes $_.Offset $_.Patched) }).Count -eq 0) -and
    (($patches.TimePatches | Where-Object { -not (Test-BytesEqual $bytes $_.Offset $_.Patched) }).Count -eq 0) -and
    (($patches.QuestStartPatches | Where-Object { -not (Test-BytesEqual $bytes $_.Offset $_.Patched) }).Count -eq 0)
)

$questStartDescription = if ($patches.QuestStartMode -eq "bridge") {
    "bridged through Remember Game Speed (.mskp)"
} else {
    "hooked directly (Remember Game Speed not installed)"
}

Write-Host "Majesty Gold HD Speedrun Timer installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Patch section: $SectionName"
Write-Host "Quest-start trigger: $questStartDescription"
if ($DryRun) {
    Write-Host "Dry run: no files will be changed."
}
Write-Host ""

if ($alreadyInstalled) {
    Write-Host "MajestyHD.exe: Speedrun Timer is already installed."
    return
}

if ($DryRun) {
    if ($layout.Existing) {
        Write-Host ("Would update {0} at file offset 0x{1:X}." -f $SectionName, $layout.PatchRaw)
    } else {
        Write-Host ("Would add {0} header at file offset 0x{1:X}." -f $SectionName, $layout.PatchHeaderOffset)
        Write-Host ("Would append {0} data at file offset 0x{1:X}." -f $SectionName, $layout.PatchRaw)
    }
    Write-Host "Would patch quest-start, victory, loss, GetTickCount, and timeGetTime update hooks."
    return
}

Assert-FileWritable $exePath

Save-PreInstallBackup $exePath $backupDir $backupPath "Speedrun Timer"

$patchedBytes = New-Object byte[] $layout.PatchedFileSize
[Array]::Copy($bytes, 0, $patchedBytes, 0, $bytes.Length)

if (-not $layout.Existing) {
    [BitConverter]::GetBytes([uint16]($layout.Pe.SectionCount + 1)).CopyTo($patchedBytes, $layout.Pe.SectionCountOffset)
    [BitConverter]::GetBytes([uint32]$layout.NewSizeOfImage).CopyTo($patchedBytes, $layout.Pe.SizeOfImageOffset)
}

Write-Bytes $patchedBytes $layout.PatchHeaderOffset $layout.Header
Write-Bytes $patchedBytes $layout.PatchRaw $layout.Blob
Write-Bytes $patchedBytes $StartHookOffset $StartOriginal

foreach ($hook in $patches.Hooks) {
    Write-Bytes $patchedBytes $hook.Offset $hook.Patched
}
foreach ($patch in $patches.LegacyQpcPatches) {
    Write-Bytes $patchedBytes $patch.Offset $QpcOriginal
}
foreach ($patch in $patches.TickPatches) {
    Write-Bytes $patchedBytes $patch.Offset $patch.Patched
}
foreach ($patch in $patches.TimePatches) {
    Write-Bytes $patchedBytes $patch.Offset $patch.Patched
}
foreach ($patch in $patches.QuestStartPatches) {
    Write-Bytes $patchedBytes $patch.Offset $patch.Patched
}

[IO.File]::WriteAllBytes($exePath, $patchedBytes)
Write-Host "Done. Start a quest and watch the title bar for 'Majesty - Speedrun Time: mm:ss.mmm'."
