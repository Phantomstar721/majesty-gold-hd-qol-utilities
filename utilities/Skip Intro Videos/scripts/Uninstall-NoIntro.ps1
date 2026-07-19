[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $PrefsPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\MajestyHD\MajXPrefs'),
    [switch] $NoBackup
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Set-MajestyIntroVideo.ps1"

Set-MajestyIntroVideo -PrefsPath $PrefsPath -Value 1 -NoBackup:$NoBackup

Write-Host 'Majesty intro videos are now enabled.'
Write-Host "Prefs: $PrefsPath"
