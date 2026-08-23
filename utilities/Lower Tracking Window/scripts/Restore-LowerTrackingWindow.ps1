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
$handlerIsStock = Test-BytesEqual $exeBytes $profile.HandlerOffset $profile.OriginalHandlerBytes
$tooltipHandlerIsStock = Test-BytesEqual $exeBytes $profile.TooltipHandlerOffset $profile.OriginalTooltipHandlerBytes
$handlerIsPatched = $false
$tooltipHandlerIsPatched = $false
$blobIsExact = $false
$blobIsInert = $false

if ($null -ne $section) {
    if ($section.RawSize -ne $script:PatchRawSize -or $section.VirtualSize -ne $script:PatchVirtualSize -or
        $section.Characteristics -ne $script:PatchSectionCharacteristics -or
        ($section.RawOffset + $section.RawSize) -gt $exeBytes.Length) {
        throw "MajestyHD.exe has an incompatible .mltw section. No files were changed."
    }
    $patchVa = [uint32]($pe.ImageBase + $section.Rva)
    [byte[]]$expectedHeader = New-SectionHeader $section.Rva $section.RawOffset
    [byte[]]$expectedBlob = New-PatchBlob $profile $patchVa
    [byte[]]$noTooltipBlob = New-NoTooltipPatchBlob $profile $patchVa
    [byte[]]$stockAutoscanIdBlob = New-StockAutoscanIdPatchBlob $profile $patchVa
    [byte[]]$previousBlob = New-PreviousPatchBlob $profile $patchVa
    [byte[]]$expectedHook = New-HandlerHook $profile $patchVa
    [byte[]]$expectedTooltipHook = New-TooltipHook $profile $patchVa
    if (-not (Test-BytesEqual $exeBytes $section.HeaderOffset $expectedHeader)) { throw "The .mltw section header is corrupt. No files were changed." }
    $handlerIsPatched = Test-BytesEqual $exeBytes $profile.HandlerOffset $expectedHook
    $tooltipHandlerIsPatched = Test-BytesEqual $exeBytes $profile.TooltipHandlerOffset $expectedTooltipHook
    $blobIsExact = Test-BytesEqual $exeBytes $section.RawOffset $expectedBlob
    $blobIsNoTooltip = Test-BytesEqual $exeBytes $section.RawOffset $noTooltipBlob
    $blobIsStockAutoscanId = Test-BytesEqual $exeBytes $section.RawOffset $stockAutoscanIdBlob
    $blobIsPrevious = Test-BytesEqual $exeBytes $section.RawOffset $previousBlob
    $blobIsInert = Test-ZeroRange $exeBytes $section.RawOffset $script:PatchRawSize
    if (-not ($handlerIsStock -or $handlerIsPatched)) { throw "The MainFrame controller hook contains unexpected bytes. No files were changed." }
    if (-not ($tooltipHandlerIsStock -or $tooltipHandlerIsPatched)) { throw "The tracking-tooltip hook contains unexpected bytes. No files were changed." }
    if ($handlerIsPatched -and -not ($blobIsExact -or $blobIsNoTooltip -or $blobIsStockAutoscanId -or $blobIsPrevious)) { throw "The MainFrame controller points to a corrupt .mltw payload. No files were changed." }
    if ($tooltipHandlerIsPatched -and -not $blobIsExact) { throw "The tracking-tooltip handler points to a corrupt .mltw payload. No files were changed." }
    if ($handlerIsStock -and $tooltipHandlerIsStock -and -not ($blobIsExact -or $blobIsNoTooltip -or $blobIsStockAutoscanId -or $blobIsPrevious -or $blobIsInert)) { throw "The inactive .mltw payload contains unexpected bytes. No files were changed." }
} elseif (-not ($handlerIsStock -and $tooltipHandlerIsStock)) {
    throw "A Lower Tracking Window hook is present but the .mltw section is missing. No files were changed."
}

$uiFiles = @(Get-ChildItem -LiteralPath $dataPath -Filter "UIData_*.dat" -File | Sort-Object Name)
if ($uiFiles.Count -eq 0) { throw "No UIData_*.dat files were found in $dataPath." }
$uiPlans = @($uiFiles | ForEach-Object { Get-UiRestorePlan $_.FullName })
$uiNeedsWrite = @($uiPlans | Where-Object Status -eq "WouldRestore")
$sectionIsLast = $null -ne $section -and $section.Index -eq ($pe.SectionCount - 1) -and $exeBytes.Length -eq ($section.RawOffset + $script:PatchRawSize)
$exeNeedsWrite = $handlerIsPatched -or $tooltipHandlerIsPatched -or ($null -ne $section -and ((-not $blobIsInert) -or $sectionIsLast))
$alreadyStock = (-not $exeNeedsWrite) -and $uiNeedsWrite.Count -eq 0

Write-Host "Majesty Gold HD Lower Tracking Window restore"
Write-Host "Game path: $resolvedGamePath"
Write-Host "Detected build: $($profile.DisplayName)"
if ($DryRun) { Write-Host "Dry run: no files will be changed." }
Write-Host ""

if ($alreadyStock) {
    Write-Host "MajestyHD.exe and all UIData layouts: stock tracking controls are already restored."
    return
}

if ($DryRun) {
    if ($handlerIsPatched) { Write-Host ("MajestyHD.exe: would restore the stock MainFrame handler at file offset 0x{0:X}." -f $profile.HandlerOffset) }
    if ($tooltipHandlerIsPatched) { Write-Host ("MajestyHD.exe: would restore the stock tracking-tooltip handler at file offset 0x{0:X}." -f $profile.TooltipHandlerOffset) }
    if ($null -ne $section -and $sectionIsLast) { Write-Host "MajestyHD.exe: would remove the trailing .mltw section." }
    elseif ($null -ne $section -and -not $blobIsInert) { Write-Host "MajestyHD.exe: would leave an inert .mltw section because later patch sections retain their addresses." }
    foreach ($plan in $uiPlans) { Write-Host ("{0}: {1}" -f (Split-Path -Leaf $plan.Path), $plan.Status) }
    return
}

Assert-FileWritable $exePath
foreach ($plan in $uiNeedsWrite) { Assert-FileWritable $plan.Path }
foreach ($plan in $uiNeedsWrite) { Write-FileAtomically $plan.Path $plan.Bytes }

if ($null -ne $section) {
    $restoredLength = if ($sectionIsLast) { [int]$section.RawOffset } else { $exeBytes.Length }
    [byte[]]$restoredExe = New-Object byte[] $restoredLength
    [Array]::Copy($exeBytes, 0, $restoredExe, 0, $restoredLength)
    if ($handlerIsPatched) { Write-Bytes $restoredExe $profile.HandlerOffset $profile.OriginalHandlerBytes }
    if ($tooltipHandlerIsPatched) { Write-Bytes $restoredExe $profile.TooltipHandlerOffset $profile.OriginalTooltipHandlerBytes }
    if ($sectionIsLast) {
        $previous = @($pe.Sections | Where-Object Index -eq ($section.Index - 1) | Select-Object -First 1)[0]
        $restoredSizeOfImage = Align-Value ([uint32]($previous.Rva + [Math]::Max($previous.VirtualSize, $previous.RawSize))) $pe.SectionAlignment
        [BitConverter]::GetBytes([uint16]($pe.SectionCount - 1)).CopyTo($restoredExe, $pe.SectionCountOffset)
        Write-U32 $restoredExe $pe.SizeOfImageOffset $restoredSizeOfImage
        Write-Bytes $restoredExe $section.HeaderOffset (New-Object byte[] 40)
    } elseif (-not $blobIsInert) {
        Write-Bytes $restoredExe $section.RawOffset (New-Object byte[] $script:PatchRawSize)
    }
    Write-FileAtomically $exePath $restoredExe
}

Write-Host "Done. The stock tracking-window interface and MainFrame controller are restored."
