param(
    [Parameter(Mandatory = $true)][string]$PublicStockExe,
    [Parameter(Mandatory = $true)][string]$Beta2StockExe
)

$ErrorActionPreference = "Stop"
$patchRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "utilities\Suppress All Message Flags"
$installScript = Join-Path $patchRoot "scripts\Install-SuppressAllMessageFlags.ps1"
$restoreScript = Join-Path $patchRoot "scripts\Restore-SuppressAllMessageFlags.ps1"
[byte[]]$stock = @(0x8B, 0x4C, 0x24, 0x10, 0x56, 0x57)
[byte[]]$patched = @(0xC3, 0x90, 0x90, 0x90, 0x90, 0x90)

$cases = @(
    [pscustomobject]@{ Name = "public-1.5.2.24"; Source = $PublicStockExe; PatchOffset = 0x48A90 },
    [pscustomobject]@{ Name = "beta2-1.5.2.28"; Source = $Beta2StockExe; PatchOffset = 0x499A0 }
)

function Assert-Bytes {
    param([string]$Path, [int]$Offset, [byte[]]$Expected, [string]$Label)
    [byte[]]$bytes = [IO.File]::ReadAllBytes($Path)
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($bytes[$Offset + $i] -ne $Expected[$i]) {
            throw "$Label failed at byte $i."
        }
    }
}

foreach ($case in $cases) {
    if (-not (Test-Path -LiteralPath $case.Source -PathType Leaf)) {
        throw "$($case.Name) stock EXE not found: $($case.Source)"
    }
    Assert-Bytes $case.Source $case.PatchOffset $stock "$($case.Name) fixture validation"

    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("majesty-message-flags-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $testExe = Join-Path $testRoot "MajestyHD.exe"
    Copy-Item -LiteralPath $case.Source -Destination $testExe

    try {
        $before = (Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash
        & $installScript -GamePath $testRoot -DryRun
        if ((Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash -ne $before) {
            throw "$($case.Name) install dry run changed the fixture."
        }

        & $installScript -GamePath $testRoot
        Assert-Bytes $testExe $case.PatchOffset $patched "$($case.Name) install"
        $installed = (Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash
        & $installScript -GamePath $testRoot
        if ((Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash -ne $installed) {
            throw "$($case.Name) repeated install was not idempotent."
        }

        & $restoreScript -GamePath $testRoot -DryRun
        Assert-Bytes $testExe $case.PatchOffset $patched "$($case.Name) restore dry run"
        & $restoreScript -GamePath $testRoot
        Assert-Bytes $testExe $case.PatchOffset $stock "$($case.Name) restore"
        if ((Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash -ne $before) {
            throw "$($case.Name) restore did not reproduce the input fixture byte-for-byte."
        }
        & $restoreScript -GamePath $testRoot
        if ((Get-FileHash -LiteralPath $testExe -Algorithm SHA256).Hash -ne $before) {
            throw "$($case.Name) repeated restore was not idempotent."
        }

        $bytes = [IO.File]::ReadAllBytes($testExe)
        $bytes[$case.PatchOffset] = 0xCC
        [IO.File]::WriteAllBytes($testExe, $bytes)
        $rejected = $false
        try { & $installScript -GamePath $testRoot } catch { $rejected = $true }
        if (-not $rejected) {
            throw "$($case.Name) installer accepted unexpected target bytes."
        }

        Write-Host "PASS: $($case.Name) dry-run, install, idempotence, restore, byte-exact roundtrip, and refusal guards."
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
