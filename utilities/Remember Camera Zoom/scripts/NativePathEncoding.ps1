function ConvertTo-MajestyNarrowPathBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$UtilityName = "This utility",
        [int]$CodePage = 0
    )

    if ($Path.IndexOf([char]0) -ge 0) {
        throw "$UtilityName cannot embed a preference path containing a null character. No game files were changed."
    }

    if ($CodePage -le 0) {
        if ($null -eq ("MajestyPathEncoding.NativeMethods" -as [type])) {
            Add-Type -Namespace MajestyPathEncoding -Name NativeMethods -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint GetACP();
"@
        }
        $CodePage = [int][MajestyPathEncoding.NativeMethods]::GetACP()
    }

    $encoding = [Text.Encoding]::GetEncoding(
        $CodePage,
        [Text.EncoderFallback]::ExceptionFallback,
        [Text.DecoderFallback]::ExceptionFallback
    )
    try {
        [byte[]]$raw = $encoding.GetBytes($Path)
    }
    catch [Text.EncoderFallbackException] {
        throw (
            "$UtilityName cannot safely store its preference path because Windows code page " +
            "$CodePage cannot represent every character in '$Path'. Majesty uses a narrow " +
            "file-path function, and lossy conversion would make saving silently fail. " +
            "No game files were changed. Use a Windows account/path supported by the " +
            "current system locale."
        )
    }

    $roundTrip = $encoding.GetString($raw)
    if (-not $roundTrip.Equals($Path, [StringComparison]::Ordinal)) {
        throw (
            "$UtilityName preference path changed during Windows code-page conversion: " +
            "'$Path' became '$roundTrip'. No game files were changed."
        )
    }

    return ,$raw
}
