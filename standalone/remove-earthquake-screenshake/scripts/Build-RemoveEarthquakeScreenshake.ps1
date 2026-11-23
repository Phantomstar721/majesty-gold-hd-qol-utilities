param(
    [string]$GamePath = "C:\Program Files (x86)\Steam\steamapps\common\Majesty HD",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $repoRoot "src"
$output = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    Join-Path $repoRoot "dist\RemoveEarthquakeScreenshake"
} elseif ([IO.Path]::IsPathRooted($OutputRoot)) {
    [IO.Path]::GetFullPath($OutputRoot)
} else {
    [IO.Path]::GetFullPath((Join-Path $repoRoot $OutputRoot))
}

$compilerCandidates = @(Join-Path $GamePath "SDK\Gplbcc.exe")
$directory = (Get-Item -LiteralPath $repoRoot).Parent
while ($directory) {
    $compilerCandidates += Join-Path $directory.FullName "external\BrandonWill-Majesty\SDK\Gplbcc.exe"
    $directory = $directory.Parent
}
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $compiler) {
    throw "Majesty GPL compiler was not found. Checked: $($compilerCandidates -join ', ')"
}

$sourceGpl = Join-Path $sourceRoot "GPL\RemoveEarthquakeScreenshake.gpl"
$sourceProject = Join-Path $sourceRoot "GPL\RemoveEarthquakeScreenshake.gplproj"
$sourceManifest = Join-Path $sourceRoot "RemoveEarthquakeScreenshake.mmxml"
foreach ($required in @($sourceGpl, $sourceProject, $sourceManifest)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required source file is missing: $required"
    }
}

$sourceText = Get-Content -LiteralPath $sourceGpl -Raw
if ($sourceText -match '(?im)^\s*\$StartEarthquakeSpell\s*\(') {
    throw "Source validation failed: the active StartEarthquakeSpell call is present."
}
foreach ($requiredCall in @('$NewThread', '$SetSpellUnitTimeout', '$earthquake_active')) {
    if ($sourceText -notmatch [regex]::Escape($requiredCall)) {
        throw "Source validation failed: required stock call is missing: $requiredCall"
    }
}

$dataDir = New-Item -ItemType Directory -Path (Join-Path $output "Data") -Force
Copy-Item -LiteralPath $sourceManifest -Destination $output
Copy-Item -LiteralPath $sourceGpl -Destination $output
$compileDir = Join-Path ([IO.Path]::GetTempPath()) ("majesty-earthquake-build-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $compileDir -Force | Out-Null
Copy-Item -LiteralPath $sourceGpl -Destination $compileDir
Copy-Item -LiteralPath $sourceProject -Destination $compileDir

Push-Location $compileDir
try {
    $compilerOutput = & $compiler -in "RemoveEarthquakeScreenshake.gplproj" -out "RemoveEarthquakeScreenshake.bcd" -stdout 2>&1
    $compilerExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
$compilerOutput | ForEach-Object { Write-Host $_ }
if ($compilerExitCode -ne 0) {
    throw "GPL compiler failed with exit code $compilerExitCode."
}

$compiled = Join-Path $compileDir "RemoveEarthquakeScreenshake.bcd"
if (-not (Test-Path -LiteralPath $compiled -PathType Leaf) -or (Get-Item -LiteralPath $compiled).Length -le 0) {
    throw "GPL compiler did not produce a nonempty BCD."
}
Move-Item -LiteralPath $compiled -Destination (Join-Path $dataDir.FullName 'RemoveEarthquakeScreenshake.bcd') -Force
if ([IO.Path]::GetFullPath($compileDir) -notlike ([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\majesty-earthquake-build-*')) {
    throw 'Temporary compiler directory escaped the expected location.'
}
Remove-Item -LiteralPath $compileDir -Recurse -Force

[xml]$manifest = Get-Content -LiteralPath (Join-Path $output "RemoveEarthquakeScreenshake.mmxml") -Raw
if ($manifest.Majesty.Mod.DataConfiguration.Dataset.Load.GPL.Target -ne 'Data\RemoveEarthquakeScreenshake.bcd') {
    throw "Manifest validation failed: compiled target path is incorrect."
}
if ($manifest.Majesty.Mod.DataConfiguration.Dataset.Load.GPL.Source -ne 'RemoveEarthquakeScreenshake.gpl') {
    throw "Manifest validation failed: matching script source must be registered."
}
if ((Get-FileHash -LiteralPath $sourceGpl).Hash -ne (Get-FileHash -LiteralPath (Join-Path $output 'RemoveEarthquakeScreenshake.gpl')).Hash) {
    throw 'Packaged source differs from the compiled input.'
}

$files = Get-ChildItem -LiteralPath $output -File -Recurse
if ($files.Count -ne 3) {
    throw "Package validation failed: expected exactly three files, found $($files.Count)."
}
Write-Host "Built Remove Earthquake Screenshake:"
Write-Host $output
Write-Host "Packaged compiled script and matching source."
