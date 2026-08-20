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
            ZoomConstructorCallVa = 0x5DDCC6
            ZoomConstructorCallOffset = 0x1DD0C6
            ZoomVtableEntryVa = 0x749288
            ZoomVtableEntryOffset = 0x348688
            ZoomRuntimeVtableEntryVa = 0x73B810
            ZoomRuntimeVtableEntryOffset = 0x33AC10
            ZoomSetterVa = 0x5DD910
            FopenIat = 0x735430
            FreadIat = 0x735434
            FwriteIat = 0x735438
            FcloseIat = 0x735444
            OriginalConstructorCallBytes = [byte[]]@(0xE8, 0x45, 0xFC, 0xFF, 0xFF)
            OriginalVtableEntryBytes = [byte[]]@(0x10, 0xD9, 0x5D, 0x00)
            OriginalRuntimeVtableEntryBytes = [byte[]]@(0x10, 0xD9, 0x5D, 0x00)
            # Public releases of this utility before the runtime-camera fix
            # owned the constructor and primary-vtable hooks as one complete
            # two-hook set. Keep that exact historical uninstall path.
            SupportsLegacyTwoHookRestore = $true
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
            ZoomConstructorCallVa = 0x5F3006
            ZoomConstructorCallOffset = 0x1F2406
            ZoomVtableEntryVa = 0x763358
            ZoomVtableEntryOffset = 0x361B58
            ZoomRuntimeVtableEntryVa = 0x7548E0
            ZoomRuntimeVtableEntryOffset = 0x3530E0
            ZoomSetterVa = 0x5F2C50
            FopenIat = 0x74E428
            FreadIat = 0x74E42C
            FwriteIat = 0x74E430
            FcloseIat = 0x74E43C
            OriginalConstructorCallBytes = [byte[]]@(0xE8, 0x45, 0xFC, 0xFF, 0xFF)
            OriginalVtableEntryBytes = [byte[]]@(0x50, 0x2C, 0x5F, 0x00)
            OriginalRuntimeVtableEntryBytes = [byte[]]@(0x50, 0x2C, 0x5F, 0x00)
            SupportsLegacyTwoHookRestore = $false
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
