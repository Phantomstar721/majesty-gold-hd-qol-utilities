[CmdletBinding()]
param(
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root.Path 'dist'
}
$dist = New-Item -ItemType Directory -Path $OutputDirectory -Force
$zipPath = Join-Path $dist.FullName 'Majesty-Gold-HD-Skip-Intro-Videos.zip'
$stage = Join-Path $env:TEMP ('majesty-no-intro-release-' + [Guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    $packageRoot = Join-Path $stage 'Majesty Gold HD - Skip Intro Videos'
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    $items = @(
        'Enable Skip Intro Videos.bat',
        'Restore Intro Videos.bat',
        'README.md',
        'LICENSE',
        'scripts'
    )

    foreach ($item in $items) {
        Copy-Item -LiteralPath (Join-Path $root.Path $item) -Destination $packageRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -Force
    Write-Host "Created: $zipPath"
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
