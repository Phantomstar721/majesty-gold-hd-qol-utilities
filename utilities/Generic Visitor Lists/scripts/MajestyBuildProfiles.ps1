function Get-MajestyBuildProfile {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $unsupported = "Unsupported MajestyHD.exe build. This utility supports the Steam Default Public Version (1.5.2.24) and beta2 Steam Multiplayer Support (1.5.2.28)."
    if ($Bytes.Length -lt 0x400) { throw $unsupported }

    try {
        if ([BitConverter]::ToUInt16($Bytes, 0) -ne 0x5A4D) { throw $unsupported }
        $peOffset = [int][BitConverter]::ToUInt32($Bytes, 0x3C)
        if ($peOffset -lt 0 -or ($peOffset + 24) -gt $Bytes.Length) { throw $unsupported }
        if ([BitConverter]::ToUInt32($Bytes, $peOffset) -ne 0x00004550) { throw $unsupported }
        if ([BitConverter]::ToUInt16($Bytes, $peOffset + 4) -ne 0x014C) { throw $unsupported }

        $sectionCount = [int][BitConverter]::ToUInt16($Bytes, $peOffset + 6)
        $timestamp = [uint32][BitConverter]::ToUInt32($Bytes, $peOffset + 8)
        $optionalSize = [int][BitConverter]::ToUInt16($Bytes, $peOffset + 20)
        $optionalOffset = $peOffset + 24
        $sectionTableOffset = $optionalOffset + $optionalSize
        if ($optionalSize -ne 0xE0 -or ($sectionTableOffset + (4 * 40)) -gt $Bytes.Length) { throw $unsupported }
        if ([BitConverter]::ToUInt16($Bytes, $optionalOffset) -ne 0x010B) { throw $unsupported }
        if ([BitConverter]::ToUInt32($Bytes, $optionalOffset + 28) -ne 0x00400000) { throw $unsupported }
        if ([BitConverter]::ToUInt32($Bytes, $optionalOffset + 32) -ne 0x1000) { throw $unsupported }
        if ([BitConverter]::ToUInt32($Bytes, $optionalOffset + 36) -ne 0x0200) { throw $unsupported }
        if ([BitConverter]::ToUInt32($Bytes, $optionalOffset + 60) -ne 0x0400) { throw $unsupported }
        if ($sectionCount -lt 4) { throw $unsupported }
        if (($sectionTableOffset + ($sectionCount * 40)) -gt 0x400) { throw $unsupported }
        for ($i = 0; $i -lt $sectionCount; $i++) {
            $offset = $sectionTableOffset + ($i * 40)
            $rawSize = [uint32][BitConverter]::ToUInt32($Bytes, $offset + 16)
            $rawOffset = [uint32][BitConverter]::ToUInt32($Bytes, $offset + 20)
            if ($rawSize -gt 0 -and ($rawOffset -lt 0x400 -or ([uint64]$rawOffset + $rawSize) -gt $Bytes.Length)) {
                throw $unsupported
            }
        }

        if ($timestamp -eq 0x5897B72F) {
            $profile = [pscustomobject]@{
                Key = "public"
                Name = "Default Public Version (1.5.2.24)"
                Timestamp = [uint32]0x5897B72F
                MinimumLength = 0x3C0600
                Sections = @(
                    @(".text",  0x333E7D, 0x001000, 0x334000, 0x000400, 0x60000020),
                    @(".rdata", 0x07E88C, 0x335000, 0x07EA00, 0x334400, 0x40000040),
                    @(".data",  0x05826C, 0x3B4000, 0x00C800, 0x3B2E00, [uint32]3221225536),
                    @(".rsrc",  0x000F34, 0x40D000, 0x001000, 0x3BF600, 0x40000040)
                )
            }
        } elseif ($timestamp -eq 0x5A8A11D5) {
            $profile = [pscustomobject]@{
                Key = "beta2"
                Name = "beta2 Steam Multiplayer Support (1.5.2.28)"
                Timestamp = [uint32]0x5A8A11D5
                MinimumLength = 0x3DE400
                Sections = @(
                    @(".text",  0x34C20D, 0x001000, 0x34C400, 0x000400, 0x60000020),
                    @(".rdata", 0x08395C, 0x34E000, 0x083A00, 0x34C800, 0x40000040),
                    @(".data",  0x058DF4, 0x3D2000, 0x00D200, 0x3D0200, [uint32]3221225536),
                    @(".rsrc",  0x000F34, 0x42B000, 0x001000, 0x3DD400, 0x40000040)
                )
            }
        } else {
            throw $unsupported
        }

        if ($Bytes.Length -lt $profile.MinimumLength) { throw $unsupported }

        for ($i = 0; $i -lt 4; $i++) {
            $expected = $profile.Sections[$i]
            $offset = $sectionTableOffset + ($i * 40)
            $name = [Text.Encoding]::ASCII.GetString($Bytes[$offset..($offset + 7)]).TrimEnd([char]0)
            if ($name -ne $expected[0] -or
                [BitConverter]::ToUInt32($Bytes, $offset + 8) -ne [uint32]$expected[1] -or
                [BitConverter]::ToUInt32($Bytes, $offset + 12) -ne [uint32]$expected[2] -or
                [BitConverter]::ToUInt32($Bytes, $offset + 16) -ne [uint32]$expected[3] -or
                [BitConverter]::ToUInt32($Bytes, $offset + 20) -ne [uint32]$expected[4] -or
                [BitConverter]::ToUInt32($Bytes, $offset + 36) -ne [uint32]$expected[5]) {
                throw $unsupported
            }
        }
        return $profile
    } catch {
        if ($_.Exception.Message -eq $unsupported) { throw }
        throw $unsupported
    }
}
