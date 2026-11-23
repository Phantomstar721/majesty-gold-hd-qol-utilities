param(
    [Parameter(Mandatory = $true)][string]$PublicStockExe,
    [Parameter(Mandatory = $true)][string]$PublicLegacyBackupDir,
    [Parameter(Mandatory = $true)][string]$Beta2StockGamePath
)

$ErrorActionPreference = "Stop"
$utilitiesRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "utilities"\n$questUtility = Join-Path $utilitiesRoot "Downloadable Quests Shortcut"
$installScript = Join-Path $questUtility "scripts\Install-DownloadableQuestShortcut.ps1"
$restoreScript = Join-Path $questUtility "scripts\Restore-CustomQuestButton.ps1"

$restoreSource = Get-Content -LiteralPath $restoreScript -Raw
if (-not $restoreSource.Contains('PreparedBytes = $newBytes')) {
    throw "Restore planning no longer retains its validated output for the write phase."
}
if ($restoreSource.Contains('Restore-UiDataOwnedFields $target $record.SourcePath | Out-Null')) {
    throw "Restore write phase reparses every UIData archive instead of using its validated plan."
}

$cases = @(
    [pscustomobject]@{
        Name = "public-1.5.2.24"
        Exe = $PublicStockExe
        Data = $null
        CallbackOffset = 0x798B6
        CompareOffset = 0x7A0FE
        StockCallback = [byte[]](0x00, 0x93, 0x47, 0x00)
        PatchedCallback = [byte[]](0x00, 0x92, 0x47, 0x00)
        UseLegacyBackups = $true
    },
    [pscustomobject]@{
        Name = "beta2-1.5.2.28"
        Exe = (Join-Path $Beta2StockGamePath "MajestyHD.exe")
        Data = (Join-Path $Beta2StockGamePath "Data")
        CallbackOffset = 0x78066
        CompareOffset = 0x789D9
        StockCallback = [byte[]](0xB0, 0x7A, 0x47, 0x00)
        PatchedCallback = [byte[]](0xB0, 0x79, 0x47, 0x00)
        UseLegacyBackups = $false
    }
)
[byte[]]$stockCompare = @(0xC2, 0x0F, 0x00, 0x00)
[byte[]]$patchedCompare = @(0x88, 0x13, 0x00, 0x00)

function Assert-Bytes {
    param([string]$Path, [int]$Offset, [byte[]]$Expected, [string]$Label)
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($bytes[$Offset + $i] -ne $Expected[$i]) {
            throw "$Label failed at byte $i."
        }
    }
}

function Get-TargetState {
    param([string]$GamePath)
    $parts = @((Get-FileHash -LiteralPath (Join-Path $GamePath "MajestyHD.exe") -Algorithm SHA256).Hash)
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $GamePath "Data") -Filter "UIData_*.dat" | Sort-Object Name)) {
        $parts += ($file.Name + ":" + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash)
    }
    return ($parts -join "|")
}

function Copy-PublicLegacyBackups {
    param([string]$GamePath, [switch]$PopulateData)
    $legacyTarget = Join-Path $GamePath "Data\_custom_quest_button_originals"
    New-Item -ItemType Directory -Path $legacyTarget -Force | Out-Null
    foreach ($backup in @(Get-ChildItem -LiteralPath $PublicLegacyBackupDir -Filter "UIData_*.dat.original" | Sort-Object Name)) {
        Copy-Item -LiteralPath $backup.FullName -Destination $legacyTarget
        if ($PopulateData) {
            $fileName = $backup.Name -replace '\.original$', ''
            Copy-Item -LiteralPath $backup.FullName -Destination (Join-Path $GamePath "Data\$fileName")
        }
    }
}

function New-StockGameFixture {
    param([object]$Case)
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("majesty-downloadable-composition-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $testRoot "Data") -Force | Out-Null
    Copy-Item -LiteralPath $Case.Exe -Destination (Join-Path $testRoot "MajestyHD.exe")
    if ($Case.UseLegacyBackups) {
        foreach ($backup in @(Get-ChildItem -LiteralPath $PublicLegacyBackupDir -Filter "UIData_*.dat.original" | Sort-Object Name)) {
            $fileName = $backup.Name -replace '\.original$', ''
            Copy-Item -LiteralPath $backup.FullName -Destination (Join-Path $testRoot "Data\$fileName")
        }
    } else {
        foreach ($uiFile in @(Get-ChildItem -LiteralPath $Case.Data -Filter "UIData_*.dat")) {
            Copy-Item -LiteralPath $uiFile.FullName -Destination (Join-Path $testRoot "Data")
        }
    }
    return $testRoot
}

function Assert-QuestLabelState {
    param([string]$GamePath, [ValidateSet("Stock","Unlock")][string]$Expected)
    $matched = 0
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $GamePath "Data") -Filter "UIData_*.dat")) {
        $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($file.FullName))
        $hasStock = $text.Contains("Cheat All Quests`0")
        $hasUnlock = $text.Contains("Unlock All Quests`0")
        if (-not $hasStock -and -not $hasUnlock) { continue }
        $matched++
        if ($Expected -eq "Stock" -and (-not $hasStock -or $hasUnlock)) {
            throw "$($file.Name) does not have only the stock Cheat All Quests label."
        }
        if ($Expected -eq "Unlock" -and (-not $hasUnlock -or $hasStock)) {
            throw "$($file.Name) does not preserve only the Unlock All Quests label."
        }
    }
    if ($matched -eq 0) { throw "No APdb quest labels were found for composition validation." }
}

function Get-ApdbDataSizeField {
    param([byte[]]$Bytes)
    $sectionCount = [BitConverter]::ToUInt32($Bytes, 12)
    for ($section = 0; $section -lt $sectionCount; $section++) {
        $directory = 20 + ($section * 8)
        $extension = [Text.Encoding]::ASCII.GetString($Bytes, $directory, 4).TrimEnd()
        if ($extension -ne "SMNU") { continue }
        $header = [int][BitConverter]::ToUInt32($Bytes, $directory + 4)
        $entryCount = [BitConverter]::ToUInt32($Bytes, $header)
        for ($entry = 0; $entry -lt $entryCount; $entry++) {
            $entryHeader = $header + 8 + ($entry * 28)
            $name = [Text.Encoding]::ASCII.GetString($Bytes, $entryHeader, 20).TrimEnd([char]0)
            if ($name -eq "APdb") { return ($entryHeader + 24) }
        }
    }
    throw "No SMNU/APdb entry found in guard fixture."
}

if (-not (Test-Path -LiteralPath $PublicStockExe -PathType Leaf)) { throw "Public EXE not found: $PublicStockExe" }
if (-not (Test-Path -LiteralPath $PublicLegacyBackupDir -PathType Container)) { throw "Public legacy backup fixture not found: $PublicLegacyBackupDir" }
if (-not (Test-Path -LiteralPath (Join-Path $Beta2StockGamePath "MajestyHD.exe") -PathType Leaf)) { throw "beta2 EXE not found under: $Beta2StockGamePath" }

foreach ($case in $cases) {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("majesty-downloadable-quests-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path (Join-Path $testRoot "Data") -Force | Out-Null
    Copy-Item -LiteralPath $case.Exe -Destination (Join-Path $testRoot "MajestyHD.exe")
    if ($case.UseLegacyBackups) {
        Copy-PublicLegacyBackups $testRoot -PopulateData
    } else {
        foreach ($uiFile in @(Get-ChildItem -LiteralPath $case.Data -Filter "UIData_*.dat")) {
            Copy-Item -LiteralPath $uiFile.FullName -Destination (Join-Path $testRoot "Data")
        }
        # A stale public backup set is deliberately present. beta2 must ignore
        # it and create/use only its beta2-scoped manifest.
        Copy-PublicLegacyBackups $testRoot
    }

    $testExe = Join-Path $testRoot "MajestyHD.exe"
    try {
        Assert-Bytes $testExe $case.CallbackOffset $case.StockCallback "$($case.Name) callback fixture"
        Assert-Bytes $testExe $case.CompareOffset $stockCompare "$($case.Name) compare fixture"
        $before = Get-TargetState $testRoot

        & $installScript -GamePath $testRoot -DryRun
        if ((Get-TargetState $testRoot) -ne $before) { throw "$($case.Name) install dry run changed a target file." }

        & $installScript -GamePath $testRoot
        Assert-Bytes $testExe $case.CallbackOffset $case.PatchedCallback "$($case.Name) callback install"
        Assert-Bytes $testExe $case.CompareOffset $patchedCompare "$($case.Name) compare install"
        $manifest = Join-Path $testRoot "Data\_custom_quest_button_originals\$($case.Name)\backup-manifest.json"
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "$($case.Name) build-scoped manifest was not created." }
        if ((Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).BuildId -ne $case.Name) { throw "$($case.Name) manifest has the wrong build ID." }

        $installed = Get-TargetState $testRoot
        & $installScript -GamePath $testRoot
        if ((Get-TargetState $testRoot) -ne $installed) { throw "$($case.Name) repeated install was not idempotent." }

        & $restoreScript -GamePath $testRoot -DryRun
        if ((Get-TargetState $testRoot) -ne $installed) { throw "$($case.Name) restore dry run changed a target file." }
        & $restoreScript -GamePath $testRoot
        if ((Get-TargetState $testRoot) -ne $before) { throw "$($case.Name) restore was not a byte-exact EXE/UIData roundtrip." }
        & $restoreScript -GamePath $testRoot
        if ((Get-TargetState $testRoot) -ne $before) { throw "$($case.Name) repeated restore was not idempotent." }

        Write-Host "PASS: $($case.Name) dry-run, install, idempotence, scoped backups, restore, and byte-exact EXE/UIData roundtrip."
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}


foreach ($case in $cases) {
    # A same-build archive with an extra APdb structural change must be refused
    # before the missing map record is inserted at a backup-relative offset.
    $guardRoot = New-StockGameFixture $case
    try {
        & $installScript -GamePath $guardRoot
        $guardFile = @(Get-ChildItem -LiteralPath (Join-Path $guardRoot "Data") -Filter "UIData_*.dat" | Where-Object {
            [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains("Cheat All Quests`0")
        } | Sort-Object Name | Select-Object -First 1)[0]
        if ($null -eq $guardFile) { throw "No applicable APdb guard fixture found." }
        [byte[]]$guardBytes = [IO.File]::ReadAllBytes($guardFile.FullName)
        $sizeField = Get-ApdbDataSizeField $guardBytes
        $changedSize = [BitConverter]::ToUInt32($guardBytes, $sizeField) + 4
        [Array]::Copy([BitConverter]::GetBytes([uint32]$changedSize), 0, $guardBytes, $sizeField, 4)
        [IO.File]::WriteAllBytes($guardFile.FullName, $guardBytes)
        $beforeRefusal = Get-TargetState $guardRoot
        $rejected = $false
        try { & $restoreScript -GamePath $guardRoot } catch { $rejected = $true }
        if (-not $rejected) { throw "$($case.Name) restore accepted an unrelated APdb size change." }
        if ((Get-TargetState $guardRoot) -ne $beforeRefusal) { throw "$($case.Name) rejected APdb insertion changed target files." }
        Write-Host "PASS: $($case.Name) refuses map insertion after an unrelated APdb structural edit."
    } finally {
        Remove-Item -LiteralPath $guardRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# A beta2 game with only old public backups must refuse restore without changing
# either the executable or UIData archives.
$hazardRoot = Join-Path ([IO.Path]::GetTempPath()) ("majesty-downloadable-quests-hazard-test-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path (Join-Path $hazardRoot "Data") -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $Beta2StockGamePath "MajestyHD.exe") -Destination $hazardRoot
foreach ($uiFile in @(Get-ChildItem -LiteralPath (Join-Path $Beta2StockGamePath "Data") -Filter "UIData_*.dat")) {
    Copy-Item -LiteralPath $uiFile.FullName -Destination (Join-Path $hazardRoot "Data")
}
Copy-PublicLegacyBackups $hazardRoot
try {
    $before = Get-TargetState $hazardRoot
    $rejected = $false
    try { & $restoreScript -GamePath $hazardRoot } catch { $rejected = $true }
    if (-not $rejected) { throw "beta2 restore accepted legacy public UIData backups." }
    if ((Get-TargetState $hazardRoot) -ne $before) { throw "Rejected cross-version restore changed a target file." }
    Write-Host "PASS: beta2 refuses unscoped public backups without changing EXE or UIData."
} finally {
    Remove-Item -LiteralPath $hazardRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$unlockScripts = Join-Path $utilitiesRoot "Unlock All Quests\scripts"
$unlockInstall = Join-Path $unlockScripts "Install-UnlockAllQuests.ps1"
$unlockRestore = Join-Path $unlockScripts "Restore-UnlockAllQuests.ps1"
if (-not (Test-Path -LiteralPath $unlockInstall -PathType Leaf) -or -not (Test-Path -LiteralPath $unlockRestore -PathType Leaf)) {
    throw "Bundled Unlock All Quests scripts are required for composition coverage."
}

foreach ($case in $cases) {
    # Downloadable snapshot is stock. Its surgical restore must leave the later
    # Unlock label installed.
    $compositionRoot = New-StockGameFixture $case
    try {
        $before = Get-TargetState $compositionRoot
        & $installScript -GamePath $compositionRoot
        & $unlockInstall -GamePath $compositionRoot
        Assert-QuestLabelState $compositionRoot Unlock
        & $restoreScript -GamePath $compositionRoot
        Assert-QuestLabelState $compositionRoot Unlock
        & $unlockRestore -GamePath $compositionRoot
        Assert-QuestLabelState $compositionRoot Stock
        if ((Get-TargetState $compositionRoot) -ne $before) {
            throw "$($case.Name) Downloadable->Unlock->restore Downloadable->restore Unlock did not roundtrip."
        }
    } finally {
        Remove-Item -LiteralPath $compositionRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Downloadable snapshot contains Unlock's label. If Unlock is removed while
    # Downloadable remains installed, Downloadable restore must not reintroduce
    # that stale label from its snapshot.
    $compositionRoot = New-StockGameFixture $case
    try {
        $before = Get-TargetState $compositionRoot
        & $unlockInstall -GamePath $compositionRoot
        & $installScript -GamePath $compositionRoot
        Assert-QuestLabelState $compositionRoot Unlock
        & $unlockRestore -GamePath $compositionRoot
        Assert-QuestLabelState $compositionRoot Stock
        & $restoreScript -GamePath $compositionRoot
        Assert-QuestLabelState $compositionRoot Stock
        if ((Get-TargetState $compositionRoot) -ne $before) {
            throw "$($case.Name) Unlock->Downloadable->restore Unlock->restore Downloadable did not roundtrip."
        }
        Write-Host "PASS: $($case.Name) Downloadable/Unlock UIData composition in both install/uninstall orders."
    } finally {
        Remove-Item -LiteralPath $compositionRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
