function Get-MajestyBuildProfiles {
    return @(
        [pscustomobject]@{
            Id = "public-1.5.2.24"
            DisplayName = "Default Public Version (1.5.2.24)"
            StockSha256 = "AA9BE61DC095773CCC5C08B9E5729A30EE856258249371C5189CE52FB675DB00"
            TimeDateStamp = [uint32]0x5897B72F
            BaseSections = @(
                @(".text",  0x001000, 0x000400, 0x334000, 0x333E7D),
                @(".rdata", 0x335000, 0x334400, 0x07EA00, 0x07E88C),
                @(".data",  0x3B4000, 0x3B2E00, 0x00C800, 0x05826C),
                @(".rsrc",  0x40D000, 0x3BF600, 0x001000, 0x000F34)
            )
            SpeedSliderSaveVa = 0x46AF18; SpeedSliderSaveOffset = 0x06A318
            SpeedStepSlowerVa = 0x4644F3; SpeedStepSlowerOffset = 0x0638F3
            SpeedStepFasterVa = 0x464595; SpeedStepFasterOffset = 0x063995
            SpeedRestoreOneVa = 0x4D90F9; SpeedRestoreOneOffset = 0x0D84F9
            SpeedRestoreTwoVa = 0x4D9B4A; SpeedRestoreTwoOffset = 0x0D8F4A
            SpeedCopyOneVa = 0x46A0C4; SpeedCopyOneOffset = 0x0694C4
            SpeedCopyTwoVa = 0x46A209; SpeedCopyTwoOffset = 0x069609
            SpeedObjectInitOneVa = 0x484DD2; SpeedObjectInitOneOffset = 0x0841D2
            SpeedObjectInitTwoVa = 0x429006; SpeedObjectInitTwoOffset = 0x028406
            SpeedObjectInitThreeVa = 0x429019; SpeedObjectInitThreeOffset = 0x028419
            OriginalSliderSaveBytes = [byte[]]@(0xA3, 0x04, 0x53, 0x7B, 0x00)
            OriginalRestoreBytes = [byte[]]@(0x89, 0x0D, 0x04, 0x53, 0x7B, 0x00)
            OriginalCopyOneBytes = [byte[]]@(0x89, 0x15, 0x04, 0x53, 0x7B, 0x00)
            OriginalCopyTwoBytes = [byte[]]@(0x89, 0x0D, 0x04, 0x53, 0x7B, 0x00)
            OriginalObjectInitOneBytes = [byte[]]@(0x89, 0x98, 0x98, 0x00, 0x00, 0x00)
            OriginalObjectInitTwoBytes = [byte[]]@(0x89, 0xB0, 0x98, 0x00, 0x00, 0x00)
            OriginalObjectInitThreeBytes = [byte[]]@(0x89, 0xB0, 0x98, 0x00, 0x00, 0x00)
            GetGameVa = 0x4D6FC0
            GameSpeedVa = 0x7B5304
            FopenIat = 0x735430; FreadIat = 0x735434; FwriteIat = 0x735438; FcloseIat = 0x735444
            SupportsLegacyHooks = $true
            OldOptionsSaveVa = 0x4881F0; OldOptionsSaveOffset = 0x0875F0
            OldOptionsRestoreVa = 0x473A8D; OldOptionsRestoreOffset = 0x072E8D
            OriginalOptionsSaveBytes = [byte[]]@(0x6A, 0xFF, 0x68, 0xAB, 0xEF, 0x6E, 0x00)
            OriginalOptionsRestoreBytes = [byte[]]@(0xE8, 0xAE, 0x19, 0x08, 0x00)
        },
        [pscustomobject]@{
            Id = "beta2-1.5.2.28"
            DisplayName = "beta2 Steam Multiplayer Support (1.5.2.28)"
            StockSha256 = "99848B5DB16CC3EA540D7E909CB24966AD9F3CD15D302CDE47AAB3BA81E3167E"
            TimeDateStamp = [uint32]0x5A8A11D5
            BaseSections = @(
                @(".text",  0x001000, 0x000400, 0x34C400, 0x34C20D),
                @(".rdata", 0x34E000, 0x34C800, 0x083A00, 0x08395C),
                @(".data",  0x3D2000, 0x3D0200, 0x00D200, 0x058DF4),
                @(".rsrc",  0x42B000, 0x3DD400, 0x001000, 0x000F34)
            )
            SpeedSliderSaveVa = 0x46C218; SpeedSliderSaveOffset = 0x06B618
            SpeedStepSlowerVa = 0x465523; SpeedStepSlowerOffset = 0x064923
            SpeedStepFasterVa = 0x4655C5; SpeedStepFasterOffset = 0x0649C5
            SpeedRestoreOneVa = 0x4D96E5; SpeedRestoreOneOffset = 0x0D8AE5
            SpeedRestoreTwoVa = 0x4DA0E9; SpeedRestoreTwoOffset = 0x0D94E9
            SpeedCopyOneVa = 0x46B304; SpeedCopyOneOffset = 0x06A704
            SpeedCopyTwoVa = 0x46B449; SpeedCopyTwoOffset = 0x06A849
            SpeedObjectInitOneVa = 0x47C0EB; SpeedObjectInitOneOffset = 0x07B4EB
            SpeedObjectInitTwoVa = 0x42ABF2; SpeedObjectInitTwoOffset = 0x029FF2
            SpeedObjectInitThreeVa = 0x42AC05; SpeedObjectInitThreeOffset = 0x02A005
            OriginalSliderSaveBytes = [byte[]]@(0xA3, 0x04, 0x33, 0x7D, 0x00)
            OriginalRestoreBytes = [byte[]]@(0xA3, 0x04, 0x33, 0x7D, 0x00)
            OriginalCopyOneBytes = [byte[]]@(0x89, 0x15, 0x04, 0x33, 0x7D, 0x00)
            OriginalCopyTwoBytes = [byte[]]@(0x89, 0x0D, 0x04, 0x33, 0x7D, 0x00)
            OriginalObjectInitOneBytes = [byte[]]@(0x89, 0x98, 0x98, 0x00, 0x00, 0x00)
            OriginalObjectInitTwoBytes = [byte[]]@(0x89, 0xB0, 0x98, 0x00, 0x00, 0x00)
            OriginalObjectInitThreeBytes = [byte[]]@(0x89, 0xB0, 0x98, 0x00, 0x00, 0x00)
            GetGameVa = 0x4D81F0
            GameSpeedVa = 0x7D3304
            FopenIat = 0x74E428; FreadIat = 0x74E42C; FwriteIat = 0x74E430; FcloseIat = 0x74E43C
            SupportsLegacyHooks = $false
            OldOptionsSaveVa = 0; OldOptionsSaveOffset = 0
            OldOptionsRestoreVa = 0; OldOptionsRestoreOffset = 0
            OriginalOptionsSaveBytes = [byte[]]@()
            OriginalOptionsRestoreBytes = [byte[]]@()
        }
    )
}

function Get-MajestyBuildProfile {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)]$Pe
    )

    $peOffset = [BitConverter]::ToUInt32($Bytes, 0x3C)
    $timeDateStamp = [BitConverter]::ToUInt32($Bytes, $peOffset + 8)
    foreach ($profile in Get-MajestyBuildProfiles) {
        if ($timeDateStamp -ne $profile.TimeDateStamp -or
            $Pe.ImageBase -ne 0x400000 -or
            $Pe.SectionAlignment -ne 0x1000 -or
            $Pe.FileAlignment -ne 0x200 -or
            $Pe.SizeOfHeaders -ne 0x400 -or
            $Pe.Sections.Count -lt $profile.BaseSections.Count) {
            continue
        }
        $matches = $true
        for ($i = 0; $i -lt $profile.BaseSections.Count; $i++) {
            $expected = $profile.BaseSections[$i]
            $actual = $Pe.Sections[$i]
            if ($actual.Name -ne $expected[0] -or
                $actual.Rva -ne $expected[1] -or
                $actual.RawOffset -ne $expected[2] -or
                $actual.RawSize -ne $expected[3] -or
                $actual.VirtualSize -ne $expected[4]) {
                $matches = $false
                break
            }
        }
        if ($matches) { return $profile }
    }

    $supported = (Get-MajestyBuildProfiles | ForEach-Object {
        "  {0}; pristine SHA-256 {1}" -f $_.DisplayName, $_.StockSha256
    }) -join [Environment]::NewLine
    throw (
        "MajestyHD.exe is not a supported Majesty Gold HD build. Supported builds:" +
        [Environment]::NewLine + $supported + [Environment]::NewLine +
        "No game files were changed."
    )
}
