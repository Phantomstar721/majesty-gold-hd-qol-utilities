param(
    [Parameter(Mandatory = $true)][string[]]$StockGamePath
)

$ErrorActionPreference = "Stop"
$bundleRoot = Split-Path -Parent $PSScriptRoot
$utilitiesRoot = Join-Path $bundleRoot "utilities"

function Utility-Script {
    param([string]$Utility, [string]$Script)
    return Join-Path (Join-Path (Join-Path $utilitiesRoot $Utility) "scripts") $Script
}

$patches = [ordered]@{
    download = [pscustomobject]@{
        Name = "Downloadable Quests Shortcut"
        Install = Utility-Script "Downloadable Quests Shortcut" "Install-DownloadableQuestShortcut.ps1"
        Restore = Utility-Script "Downloadable Quests Shortcut" "Restore-CustomQuestButton.ps1"
        InstalledPhrase = "alreadypatched"
    }
    map = [pscustomobject]@{
        Name = "Quest Map Drag"
        Install = Utility-Script "Quest Map Drag" "Install-QuestMapDragPan.ps1"
        Restore = Utility-Script "Quest Map Drag" "Restore-QuestMapDragPan.ps1"
        InstalledPhrase = "already installed"
    }
    unlock = [pscustomobject]@{
        Name = "Unlock All Quests"
        Install = Utility-Script "Unlock All Quests" "Install-UnlockAllQuests.ps1"
        Restore = Utility-Script "Unlock All Quests" "Restore-UnlockAllQuests.ps1"
        InstalledPhrase = "would leave installed"
    }
    suppress = [pscustomobject]@{
        Name = "Suppress All Message Flags"
        Install = Utility-Script "Suppress All Message Flags" "Install-SuppressAllMessageFlags.ps1"
        Restore = Utility-Script "Suppress All Message Flags" "Restore-SuppressAllMessageFlags.ps1"
        InstalledPhrase = "already suppressed"
    }
    mods = [pscustomobject]@{
        Name = "Remember Active Mods"
        Install = Utility-Script "Remember Active Mods" "Install-ModPersistence.ps1"
        Restore = Utility-Script "Remember Active Mods" "Restore-ModPersistence.ps1"
        InstalledPhrase = "already installed"
    }
    speed = [pscustomobject]@{
        Name = "Remember Game Speed"
        Install = Utility-Script "Remember Game Speed" "Install-RememberGameSpeed.ps1"
        Restore = Utility-Script "Remember Game Speed" "Restore-RememberGameSpeed.ps1"
        InstalledPhrase = "already installed"
    }
    zoom = [pscustomobject]@{
        Name = "Remember Camera Zoom"
        Install = Utility-Script "Remember Camera Zoom" "Install-RememberCameraZoom.ps1"
        Restore = Utility-Script "Remember Camera Zoom" "Restore-RememberCameraZoom.ps1"
        InstalledPhrase = "already installed"
    }
    visitors = [pscustomobject]@{
        Name = "Generic Visitor Lists"
        Install = Utility-Script "Generic Visitor Lists" "Install-GenericVisitorLists.ps1"
        Restore = Utility-Script "Generic Visitor Lists" "Restore-GenericVisitorLists.ps1"
        InstalledPhrase = "threat ranks are already installed"
    }
}

$scenarios = @(
    [pscustomobject]@{
        Name = "download-before-unlock"
        Install = @("download", "map", "unlock", "suppress", "mods", "speed", "zoom", "visitors")
        Restore = @("download", "mods", "unlock", "visitors", "speed", "map", "zoom", "suppress")
    },
    [pscustomobject]@{
        Name = "unlock-before-download"
        Install = @("visitors", "zoom", "speed", "mods", "suppress", "unlock", "map", "download")
        Restore = @("unlock", "download", "map", "suppress", "mods", "speed", "zoom", "visitors")
    }
)

function Get-TargetSnapshot {
    param([string]$GamePath)
    $result = [ordered]@{}
    $exe = Join-Path $GamePath "MajestyHD.exe"
    $result["MajestyHD.exe"] = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    $dataPath = Join-Path $GamePath "Data"
    foreach ($file in Get-ChildItem -LiteralPath $dataPath -Filter "UIData_*.dat" -File | Sort-Object Name) {
        $result[("Data\" + $file.Name)] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $result
}

function Assert-SnapshotEqual {
    param([System.Collections.IDictionary]$Expected, [System.Collections.IDictionary]$Actual, [string]$Label)
    if ($Expected.Count -ne $Actual.Count) { throw "$Label changed the target-file count." }
    foreach ($key in $Expected.Keys) {
        if (-not $Actual.Contains($key) -or $Actual[$key] -ne $Expected[$key]) {
            throw "$Label changed $key."
        }
    }
}

function Invoke-PatchScript {
    param([string]$Script, [string]$GamePath, [switch]$DryRun)
    if ($DryRun) {
        return (& $Script -GamePath $GamePath -DryRun *>&1 | Out-String)
    }
    return (& $Script -GamePath $GamePath *>&1 | Out-String)
}

function Test-InstalledOutput {
    param([pscustomobject]$Patch, [string]$Output)
    $lowered = $Output.ToLowerInvariant()
    return $lowered.Contains($Patch.InstalledPhrase) -and -not $lowered.Contains("wouldpatch")
}

function Assert-UtilityStates {
    param([string]$GamePath, [string[]]$InstalledKeys, [string[]]$RemovedKeys, [string]$Label)
    foreach ($key in $InstalledKeys) {
        $patch = $patches[$key]
        $output = Invoke-PatchScript $patch.Install $GamePath -DryRun
        if (-not (Test-InstalledOutput $patch $output)) {
            throw "$Label disturbed installed utility '$($patch.Name)'.`n$output"
        }
    }
    foreach ($key in $RemovedKeys) {
        $patch = $patches[$key]
        $output = Invoke-PatchScript $patch.Install $GamePath -DryRun
        if (Test-InstalledOutput $patch $output) {
            throw "$Label reinstalled or failed to remove '$($patch.Name)'.`n$output"
        }
    }
}

foreach ($stockRoot in $StockGamePath) {
    $stockExe = Join-Path $stockRoot "MajestyHD.exe"
    $stockData = Join-Path $stockRoot "Data"
    if (-not (Test-Path -LiteralPath $stockExe -PathType Leaf)) { throw "Stock EXE not found: $stockExe" }
    $uiFiles = @(Get-ChildItem -LiteralPath $stockData -Filter "UIData_*.dat" -File -ErrorAction SilentlyContinue)
    if ($uiFiles.Count -lt 1) { throw "No stock UIData files found under $stockData" }

    [byte[]]$stockBytes = [IO.File]::ReadAllBytes($stockExe)
    $peOffset = [BitConverter]::ToInt32($stockBytes, 0x3C)
    $timestamp = [BitConverter]::ToUInt32($stockBytes, $peOffset + 8)
    $buildName = if ($timestamp -eq 0x5897B72F) { "public" } elseif ($timestamp -eq 0x5A8A11D5) { "beta2" } else { throw "Unsupported fixture build timestamp 0x$($timestamp.ToString('X8'))." }

    foreach ($scenario in $scenarios) {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("majesty-all-qol-test-" + [Guid]::NewGuid().ToString("N"))
        $testData = Join-Path $testRoot "Data"
        New-Item -ItemType Directory -Path $testData | Out-Null
        Copy-Item -LiteralPath $stockExe -Destination (Join-Path $testRoot "MajestyHD.exe")
        foreach ($uiFile in $uiFiles) { Copy-Item -LiteralPath $uiFile.FullName -Destination $testData }

        try {
            $stockSnapshot = Get-TargetSnapshot $testRoot
            foreach ($key in $scenario.Install) {
                $null = Invoke-PatchScript $patches[$key].Install $testRoot
            }
            Assert-UtilityStates $testRoot $scenario.Install @() "Initial install"
            $installedSnapshot = Get-TargetSnapshot $testRoot

            foreach ($key in $scenario.Install) {
                $null = Invoke-PatchScript $patches[$key].Install $testRoot
            }
            Assert-SnapshotEqual $installedSnapshot (Get-TargetSnapshot $testRoot) "Repeated install"

            $remaining = @($scenario.Install)
            $removed = @()
            foreach ($key in $scenario.Restore) {
                $null = Invoke-PatchScript $patches[$key].Restore $testRoot
                $remaining = @($remaining | Where-Object { $_ -ne $key })
                $removed += $key
                Assert-UtilityStates $testRoot $remaining $removed ("Restoring " + $patches[$key].Name)
            }

            # Appended sections that were not last at first removal become inert.
            # Repeat guarded restores after all hooks are stock so each trailing
            # inert section can be physically removed in turn.
            for ($pass = 0; $pass -lt 4; $pass++) {
                foreach ($key in $scenario.Restore) {
                    $null = Invoke-PatchScript $patches[$key].Restore $testRoot
                }
            }
            Assert-SnapshotEqual $stockSnapshot (Get-TargetSnapshot $testRoot) "Complete restore"
            Write-Host "PASS [$buildName/$($scenario.Name)]: all executable/UIData utilities remained independent and restored byte-exactly."
        } finally {
            $resolved = [IO.Path]::GetFullPath($testRoot)
            $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            if (-not $resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing cleanup outside the temporary directory."
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
