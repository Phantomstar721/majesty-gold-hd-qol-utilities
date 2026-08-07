param([string]$OutputDir = "", [switch]$KeepBuildFiles)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildVenv = Join-Path $RepoRoot ".venv-build"
$SharedBuildPython = Join-Path (Split-Path -Parent $RepoRoot) "majesty-gold-hd-art-asset-extractor\.venv-build\Scripts\python.exe"
$Work = Join-Path $RepoRoot ".tmp\pyinstaller"
if (-not $OutputDir) { $OutputDir = $RepoRoot }

if (Test-Path $SharedBuildPython) {
    # Reuse the extractor's workspace-local packager when these sibling repos
    # are checked out together. A standalone clone still creates its own.
    $Python = $SharedBuildPython
} else {
    if (-not (Test-Path (Join-Path $BuildVenv "Scripts\python.exe"))) {
        py -3 -m venv $BuildVenv
        if ($LASTEXITCODE -ne 0) { throw "Could not create the build environment." }
    }
    $Python = Join-Path $BuildVenv "Scripts\python.exe"
}
& $Python -c "import PyInstaller" 2>$null
if ($LASTEXITCODE -ne 0) {
    & $Python -m pip install --disable-pip-version-check --quiet pyinstaller
    if ($LASTEXITCODE -ne 0) { throw "Could not install PyInstaller." }
}

& $Python -m PyInstaller --noconfirm --clean --onefile --windowed --uac-admin `
    --name "Majesty QoL Utilities" --distpath $OutputDir --workpath $Work --specpath $Work `
    --paths $PSScriptRoot --add-data "$(Join-Path $RepoRoot 'utilities');utilities" `
    (Join-Path $PSScriptRoot "majesty_qol_utilities.py")
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed with exit code $LASTEXITCODE." }
if (-not $KeepBuildFiles) { Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Built $(Join-Path $OutputDir 'Majesty QoL Utilities.exe')"
