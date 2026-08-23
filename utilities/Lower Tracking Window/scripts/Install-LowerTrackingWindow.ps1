param(
    [string]$GamePath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "PatchCommon.ps1")

$resolvedGamePath = Get-MajestyPath $GamePath
$exePath = Join-Path $resolvedGamePath "MajestyHD.exe"
$dataPath = Join-Path $resolvedGamePath "Data"
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) { throw "Could not find MajestyHD.exe at $exePath." }
if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) { throw "Could not find Majesty Data at $dataPath." }

[byte[]]$exeBytes = [IO.File]::ReadAllBytes($exePath)
$pe = Get-PeInfo $exeBytes
$profile = Get-MajestyBuildProfile $exeBytes $pe
$section = @($pe.Sections | Where-Object Name -eq $script:PatchSectionName | Select-Object -First 1)[0]

if ($null -ne $section) {
    if ($section.RawSize -ne $script:PatchRawSize -or $section.VirtualSize -ne $script:PatchVirtualSize -or
        $section.Characteristics -ne $script:PatchSectionCharacteristics -or
        ($section.RawOffset + $section.RawSize) -gt $exeBytes.Length) {
        throw "MajestyHD.exe has an incompatible .mltw section. Refusing to guess."
    }
    $patchRva = [uint32]$section.Rva
    $patchRawOffset = [uint32]$section.RawOffset
    $patchHeaderOffset = [int]$section.HeaderOffset
    $patchHeader = New-SectionHeader $patchRva $patchRawOffset
    $addsSection = $false
} else {
    $lastSection = @($pe.Sections | Sort-Object RawOffset | Select-Object -Last 1)[0]
    $patchRawOffset = Align-Value ([uint32]$exeBytes.Length) $pe.FileAlignment
    if ($patchRawOffset -ne $exeBytes.Length) { throw "MajestyHD.exe has unaligned trailing data. Refusing to append a patch section." }
    $lastVirtualEnd = [uint32]($lastSection.Rva + [Math]::Max($lastSection.VirtualSize, $lastSection.RawSize))
    $patchRva = Align-Value $lastVirtualEnd $pe.SectionAlignment
    $patchHeaderOffset = [int]($pe.SectionTableOffset + ($pe.SectionCount * 40))
    if (($patchHeaderOffset + 40) -gt $pe.SizeOfHeaders -or -not (Test-ZeroRange $exeBytes $patchHeaderOffset 40)) {
        throw "No empty PE header slot remains for the .mltw patch section."
    }
    $patchHeader = New-SectionHeader $patchRva $patchRawOffset
    $addsSection = $true
}

$patchVa = [uint32]($pe.ImageBase + $patchRva)
[byte[]]$patchBlob = New-PatchBlob $profile $patchVa
[byte[]]$noTooltipPatchBlob = New-NoTooltipPatchBlob $profile $patchVa
[byte[]]$stockAutoscanIdPatchBlob = New-StockAutoscanIdPatchBlob $profile $patchVa
[byte[]]$previousPatchBlob = New-PreviousPatchBlob $profile $patchVa
[byte[]]$patchedHandler = New-HandlerHook $profile $patchVa
[byte[]]$patchedTooltipHandler = New-TooltipHook $profile $patchVa
$handlerIsStock = Test-BytesEqual $exeBytes $profile.HandlerOffset $profile.OriginalHandlerBytes
$handlerIsPatched = Test-BytesEqual $exeBytes $profile.HandlerOffset $patchedHandler
if (-not ($handlerIsStock -or $handlerIsPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the stock MainFrame controller handler (file offset 0x{0:X})." -f $profile.HandlerOffset)
}
$tooltipHandlerIsStock = Test-BytesEqual $exeBytes $profile.TooltipHandlerOffset $profile.OriginalTooltipHandlerBytes
$tooltipHandlerIsPatched = Test-BytesEqual $exeBytes $profile.TooltipHandlerOffset $patchedTooltipHandler
if (-not ($tooltipHandlerIsStock -or $tooltipHandlerIsPatched)) {
    throw ("MajestyHD.exe has unexpected bytes at the stock tracking-tooltip handler (file offset 0x{0:X})." -f $profile.TooltipHandlerOffset)
}
if ($null -ne $section) {
    $headerIsExact = Test-BytesEqual $exeBytes $patchHeaderOffset $patchHeader
    $blobIsExact = Test-BytesEqual $exeBytes $patchRawOffset $patchBlob
    $blobIsNoTooltip = Test-BytesEqual $exeBytes $patchRawOffset $noTooltipPatchBlob
    $blobIsStockAutoscanId = Test-BytesEqual $exeBytes $patchRawOffset $stockAutoscanIdPatchBlob
    $blobIsPrevious = Test-BytesEqual $exeBytes $patchRawOffset $previousPatchBlob
    $blobIsInert = Test-ZeroRange $exeBytes $patchRawOffset $script:PatchRawSize
    if (-not $headerIsExact -or -not ($blobIsExact -or $blobIsNoTooltip -or $blobIsStockAutoscanId -or $blobIsPrevious -or ($blobIsInert -and $handlerIsStock -and $tooltipHandlerIsStock))) {
        throw "The existing .mltw section is neither the exact installed patch nor a safely reusable inert section."
    }
    if ($tooltipHandlerIsPatched -and -not $blobIsExact) {
        throw "The tracking-tooltip handler points to an incompatible .mltw payload."
    }
} else {
    $blobIsExact = $false
    $blobIsNoTooltip = $false
    $blobIsStockAutoscanId = $false
    $blobIsPrevious = $false
}

$uiFiles = @(Get-ChildItem -LiteralPath $dataPath -Filter "UIData_*.dat" -File | Sort-Object Name)
if ($uiFiles.Count -eq 0) { throw "No UIData_*.dat files were found in $dataPath." }
$uiPlans = @($uiFiles | ForEach-Object { Get-UiInstallPlan $_.FullName })
$uiNeedsWrite = @($uiPlans | Where-Object Status -in @("WouldPatch", "WouldUpgrade", "WouldRelocate"))
$applicableUi = @($uiPlans | Where-Object Status -ne "SkippedNoLowerWindow")
if ($applicableUi.Count -eq 0) { throw "No installed UIData layout exposes Majesty's stock lower tracking window." }
$alreadyInstalled = (-not $addsSection) -and $handlerIsPatched -and $tooltipHandlerIsPatched -and $blobIsExact -and $uiNeedsWrite.Count -eq 0

Write-Host "Majesty Gold HD Lower Tracking Window installer"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Detected build: $($profile.DisplayName)"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($alreadyInstalled) {
    Write-Host "MajestyHD.exe and all UIData layouts: Lower Tracking Window is already installed."
    return
}

if ($DryRun) {
    if ($addsSection) { Write-Host ("MajestyHD.exe: would append .mltw at file offset 0x{0:X}." -f $patchRawOffset) }
    elseif ($blobIsNoTooltip) { Write-Host "MajestyHD.exe: would add the stock-style Track Selected tooltip route." }
    elseif ($blobIsStockAutoscanId) { Write-Host "MajestyHD.exe: would privatize the lower Autoscan control route." }
    elseif ($blobIsPrevious) { Write-Host "MajestyHD.exe: would upgrade the earlier selection resolver." }
    elseif (-not $blobIsExact) { Write-Host "MajestyHD.exe: would reactivate its inert .mltw section." }
    if (-not $handlerIsPatched) { Write-Host ("MajestyHD.exe: would hook the MainFrame controller at file offset 0x{0:X}." -f $profile.HandlerOffset) }
    if (-not $tooltipHandlerIsPatched) { Write-Host ("MajestyHD.exe: would hook the tracking-tooltip handler at file offset 0x{0:X}." -f $profile.TooltipHandlerOffset) }
    foreach ($plan in $uiPlans) { Write-Host ("{0}: {1}" -f (Split-Path -Leaf $plan.Path), $plan.Status) }
    return
}

Assert-FileWritable $exePath
foreach ($plan in $uiNeedsWrite) { Assert-FileWritable $plan.Path }

foreach ($plan in $uiNeedsWrite) {
    Write-FileAtomically $plan.Path $plan.Bytes
}

$targetLength = if ($addsSection) { [int]($patchRawOffset + $script:PatchRawSize) } else { $exeBytes.Length }
[byte[]]$patchedExe = New-Object byte[] $targetLength
[Array]::Copy($exeBytes, 0, $patchedExe, 0, $exeBytes.Length)
if ($addsSection) {
    [BitConverter]::GetBytes([uint16]($pe.SectionCount + 1)).CopyTo($patchedExe, $pe.SectionCountOffset)
    $newSizeOfImage = Align-Value ([uint32]($patchRva + $script:PatchVirtualSize)) $pe.SectionAlignment
    Write-U32 $patchedExe $pe.SizeOfImageOffset $newSizeOfImage
}
Write-Bytes $patchedExe $patchHeaderOffset $patchHeader
Write-Bytes $patchedExe $patchRawOffset $patchBlob
Write-Bytes $patchedExe $profile.HandlerOffset $patchedHandler
Write-Bytes $patchedExe $profile.TooltipHandlerOffset $patchedTooltipHandler
Write-FileAtomically $exePath $patchedExe

Write-Host ("Done. The lower Autoscan control now tracks the selected target in slot 2 in {0} applicable UI layout(s)." -f $applicableUi.Count)
