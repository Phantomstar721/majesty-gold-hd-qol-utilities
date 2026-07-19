function Set-MajestyIntroVideo {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $PrefsPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet(0, 1)]
        [int] $Value,

        [switch] $NoBackup
    )

    $parent = Split-Path -Parent $PrefsPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $PrefsPath)) {
        $newPrefs = "<DataGroups>`r`n`t<IntroVideo>$Value</IntroVideo>`r`n</DataGroups>`r`n"
        if ($PSCmdlet.ShouldProcess($PrefsPath, 'create Majesty preferences file')) {
            Set-Content -LiteralPath $PrefsPath -Value $newPrefs -NoNewline -Encoding ASCII
        }
        return
    }

    $raw = Get-Content -LiteralPath $PrefsPath -Raw

    try {
        [xml] $xml = $raw
    }
    catch {
        throw "Cannot update '$PrefsPath' because it is not valid XML. No changes were made."
    }

    if ($xml.DocumentElement.Name -ne 'DataGroups') {
        throw "Cannot update '$PrefsPath' because the root element is not DataGroups. No changes were made."
    }

    if (-not $NoBackup) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = "$PrefsPath.no-intro-backup.$stamp"
        if ($PSCmdlet.ShouldProcess($backupPath, 'write backup')) {
            Copy-Item -LiteralPath $PrefsPath -Destination $backupPath -Force
            Write-Host "Backup: $backupPath"
        }
    }

    if ($raw -match '<IntroVideo>.*?</IntroVideo>') {
        $updated = [regex]::Replace(
            $raw,
            '<IntroVideo>.*?</IntroVideo>',
            "<IntroVideo>$Value</IntroVideo>",
            1
        )
    }
    else {
        $updated = [regex]::Replace(
            $raw,
            '</DataGroups>',
            "`t<IntroVideo>$Value</IntroVideo>`r`n</DataGroups>",
            1
        )
    }

    if ($PSCmdlet.ShouldProcess($PrefsPath, "set IntroVideo to $Value")) {
        Set-Content -LiteralPath $PrefsPath -Value $updated -NoNewline -Encoding ASCII
    }
}
