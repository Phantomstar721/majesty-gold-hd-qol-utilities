$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot "src\GPL\RemoveEarthquakeScreenshake.gpl"
$text = Get-Content -LiteralPath $source -Raw

if (($text | Select-String -Pattern '(?im)^function\s+Earthquake_Unit_Created\s*\(' -AllMatches).Matches.Count -ne 1) {
    throw "Expected exactly one Earthquake_Unit_Created replacement."
}
if ($text -match '(?im)^\s*\$StartEarthquakeSpell\s*\(') {
    throw "The native screenshake call is still active."
}
foreach ($requiredCall in @('$NewThread', '$SetSpellUnitTimeout', '$earthquake_active')) {
    if ($text -notmatch [regex]::Escape($requiredCall)) {
        throw "Required stock lifecycle call is missing: $requiredCall"
    }
}

& (Join-Path $repoRoot "scripts\Build-RemoveEarthquakeScreenshake.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "Build script failed."
}

$package = Join-Path $repoRoot "dist\RemoveEarthquakeScreenshake"
$expected = @(
    "RemoveEarthquakeScreenshake.mmxml",
    "RemoveEarthquakeScreenshake.gpl",
    "Data\RemoveEarthquakeScreenshake.bcd"
)
foreach ($relative in $expected) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $relative) -PathType Leaf)) {
        throw "Package file is missing: $relative"
    }
}
$actual = Get-ChildItem -LiteralPath $package -File -Recurse
if ($actual.Count -ne 3) {
    throw "Expected a three-file package; found $($actual.Count) files."
}
[xml]$manifest = Get-Content -LiteralPath (Join-Path $package 'RemoveEarthquakeScreenshake.mmxml') -Raw
if ($manifest.Majesty.Mod.DataConfiguration.Dataset.Load.GPL.Source -ne 'RemoveEarthquakeScreenshake.gpl') {
    throw 'The manifest must register the matching source.'
}
if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath (Join-Path $package 'RemoveEarthquakeScreenshake.gpl')).Hash) {
    throw 'Packaged source does not match compiler input.'
}
