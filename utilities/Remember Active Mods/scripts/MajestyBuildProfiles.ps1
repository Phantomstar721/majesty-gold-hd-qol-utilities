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
            LoadCallOffset = 0x077D30
            LoadCallVa = 0x478930
            SaveCallOffset = 0x124196
            SaveCallVa = 0x524D96
            ApplyActiveModsVa = 0x525540
            ModsOkHandlerVa = 0x5253E0
            ActiveListInsertVa = 0x522340
            ActiveListCommitVa = 0x5223F0
            FprintfIat = 0x7353E0
            FopenIat = 0x735430
            FreadIat = 0x735434
            FcloseIat = 0x735444
            SscanfIat = 0x73544C
            InstalledListVa = 0x7C1E30
            ActiveListOwnerVa = 0x7C1E38
            ActiveListVa = 0x7C1E4C
            ActiveListDirtyVa = 0x7C1DFC
            PatchSectionCharacteristics = [uint32]0x60000020
            UsePrivateScratchArena = $false
            OriginalLoadCall = [byte[]]@(0xE8, 0xAB, 0xCA, 0x0A, 0x00)
            OriginalSaveCall = [byte[]]@(0xE8, 0xA5, 0x07, 0x00, 0x00)
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
            LoadCallOffset = 0x076490
            LoadCallVa = 0x477090
            SaveCallOffset = 0x138A56
            SaveCallVa = 0x539656
            ApplyActiveModsVa = 0x539E00
            ModsOkHandlerVa = 0x539CA0
            ActiveListInsertVa = 0x536C00
            ActiveListCommitVa = 0x536CB0
            FprintfIat = 0x74E3E0
            FopenIat = 0x74E428
            FreadIat = 0x74E42C
            FcloseIat = 0x74E43C
            SscanfIat = 0x74E450
            InstalledListVa = 0x7E09A0
            ActiveListOwnerVa = 0x7E09A8
            ActiveListVa = 0x7E09BC
            ActiveListDirtyVa = 0x7E096C
            PatchSectionCharacteristics = [uint32]3758096416 # 0xE0000020
            UsePrivateScratchArena = $true
            OriginalLoadCall = [byte[]]@(0xE8, 0x0B, 0x2C, 0x0C, 0x00)
            OriginalSaveCall = [byte[]]@(0xE8, 0xA5, 0x07, 0x00, 0x00)
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
        if ($matches) {
            return $profile
        }
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
