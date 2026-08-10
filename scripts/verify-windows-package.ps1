param(
    [string]$RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "..")
    ),
    [string]$AppName,
    [string]$BundleId,
    [switch]$RunPeParserSelfTests
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AppName) -or
    [string]::IsNullOrWhiteSpace($BundleId)) {
    $identityJson = & node (
        Join-Path $RepositoryRoot "scripts/app-identity.mjs"
    ) prepare --format json
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to resolve Buwiz app identity."
    }
    $identity = $identityJson | ConvertFrom-Json
    $AppName = [string]$identity.appName
    $BundleId = [string]$identity.bundleId
}

$installedExe = Join-Path $RepositoryRoot ("zig-out\bin\$AppName.exe")
$packageRoot = Join-Path $RepositoryRoot (
    "zig-out\package\$AppName-windows"
)
$packagedExe = Join-Path $packageRoot ("bin\$AppName.exe")
$manifestPath = Join-Path $packageRoot "package-manifest.zon"
$inventoryPath = Join-Path $RepositoryRoot (
    "zig-out\package\$AppName-windows-package-inventory.txt"
)

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)] $Actual,
        [Parameter(Mandatory = $true)] $Expected,
        [Parameter(Mandatory = $true)] [string] $Label
    )

    if ($Actual -ne $Expected) {
        throw (
            "$Label mismatch. Expected '$Expected'; observed '$Actual'."
        )
    }
}

function Assert-PeSectionLayout {
    param(
        [Parameter(Mandatory = $true)] [object[]] $Sections,
        [Parameter(Mandatory = $true)] [int] $FileLength
    )

    $previousStart = $null
    $previousEnd = [uint64]0
    for ($index = 0; $index -lt $Sections.Count; $index++) {
        $section = $Sections[$index]
        $sectionStart = [uint64]$section.VirtualAddress
        $virtualExtent = [uint64]$section.VirtualSize
        if ($virtualExtent -eq 0) {
            $virtualExtent = [uint64]$section.RawSize
        }
        $addressExtent = $virtualExtent
        if ([uint64]$section.RawSize -gt $addressExtent) {
            $addressExtent = [uint64]$section.RawSize
        }
        $sectionEnd = $sectionStart + $addressExtent
        if ($sectionEnd -gt 0x100000000L) {
            throw "PE section RVA range overflows the 32-bit address space."
        }

        if ($null -ne $previousStart) {
            if ($sectionStart -le $previousStart) {
                throw "PE section RVAs are not strictly ascending."
            }
            if ($sectionStart -lt $previousEnd) {
                throw "PE section RVA ranges overlap."
            }
        }

        $rawEnd = (
            [uint64]$section.RawPointer + [uint64]$section.RawSize
        )
        if ($rawEnd -gt [uint64]$FileLength) {
            throw "PE section raw-data range extends outside the file."
        }

        $previousStart = $sectionStart
        $previousEnd = $sectionEnd
    }
}

function Convert-PeRvaToFileOffset {
    param(
        [Parameter(Mandatory = $true)] [uint32] $Rva,
        [Parameter(Mandatory = $true)] [uint32] $Size,
        [Parameter(Mandatory = $true)] [uint32] $SizeOfHeaders,
        [Parameter(Mandatory = $true)] [object[]] $Sections,
        [Parameter(Mandatory = $true)] [int] $FileLength
    )

    if ($Size -eq 0) {
        throw "PE RVA mapping requires a non-empty range."
    }
    $rvaEnd = [uint64]$Rva + [uint64]$Size
    if ($rvaEnd -gt 0x100000000L) {
        throw "PE RVA range overflows the 32-bit address space."
    }

    $candidates = @()
    if (
        $Rva -lt $SizeOfHeaders -and
        $rvaEnd -le [uint64]$SizeOfHeaders -and
        $rvaEnd -le [uint64]$FileLength
    ) {
        $candidates += [PSCustomObject]@{
            Offset = [uint64]$Rva
            Source = "headers"
        }
    }

    foreach ($section in $Sections) {
        $sectionStart = [uint64]$section.VirtualAddress
        $virtualExtent = [uint64]$section.VirtualSize
        if ($virtualExtent -eq 0) {
            $virtualExtent = [uint64]$section.RawSize
        }
        $virtualEnd = $sectionStart + $virtualExtent
        $rawBackedEnd = $sectionStart + [uint64]$section.RawSize
        if (
            [uint64]$Rva -ge $sectionStart -and
            $rvaEnd -le $virtualEnd -and
            $rvaEnd -le $rawBackedEnd
        ) {
            $offset = [uint64]$section.RawPointer +
                ([uint64]$Rva - $sectionStart)
            $offsetEnd = $offset + [uint64]$Size
            if ($offsetEnd -gt $FileLength) {
                throw "PE RVA maps outside the file."
            }
            $candidates += [PSCustomObject]@{
                Offset = $offset
                Source = "section"
            }
        }
    }

    if ($candidates.Count -eq 0) {
        throw (
            "PE RVA does not map within both the virtual and raw-backed " +
            "extent of one file location."
        )
    }
    if ($candidates.Count -ne 1) {
        throw "PE RVA maps ambiguously to multiple file locations."
    }
    if ($candidates[0].Offset -gt [int]::MaxValue) {
        throw "PE RVA file offset exceeds the supported file size."
    }
    return [int]$candidates[0].Offset
}

function Get-PeIdentity {
    param(
        [Parameter(Mandatory = $true)] [string] $Path
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x100) {
        throw "PE file is unexpectedly short: $Path"
    }
    Assert-Equal ([BitConverter]::ToUInt16($bytes, 0)) 0x5A4D (
        "DOS signature"
    )

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or $peOffset + 0x60 -gt $bytes.Length) {
        throw "PE header offset is outside the file: $Path"
    }
    Assert-Equal ([BitConverter]::ToUInt32($bytes, $peOffset)) 0x00004550 (
        "PE signature"
    )

    $sectionCount = [BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $optionalHeaderSize = [BitConverter]::ToUInt16(
        $bytes,
        $peOffset + 20
    )
    $optionalHeaderOffset = $peOffset + 24
    $optionalHeaderEnd = $optionalHeaderOffset + $optionalHeaderSize
    if ($optionalHeaderEnd -gt $bytes.Length) {
        throw "PE optional header extends outside the file: $Path"
    }
    if ($optionalHeaderOffset + 2 -gt $optionalHeaderEnd) {
        throw "PE optional header omits its magic: $Path"
    }
    $magic = [BitConverter]::ToUInt16($bytes, $optionalHeaderOffset)
    $dataDirectoryOffset = switch ($magic) {
        0x020B { $optionalHeaderOffset + 112 }
        0x010B { $optionalHeaderOffset + 96 }
        default { throw "Unsupported PE optional-header magic: $magic" }
    }
    $numberOfRvaAndSizesOffset = switch ($magic) {
        0x020B { $optionalHeaderOffset + 108 }
        0x010B { $optionalHeaderOffset + 92 }
        default { throw "Unsupported PE optional-header magic: $magic" }
    }
    if ($numberOfRvaAndSizesOffset + 4 -gt $optionalHeaderEnd) {
        throw "PE optional header omits NumberOfRvaAndSizes."
    }
    $numberOfRvaAndSizes = [BitConverter]::ToUInt32(
        $bytes,
        $numberOfRvaAndSizesOffset
    )
    if ($numberOfRvaAndSizes -lt 7) {
        throw "PE optional header declares fewer than seven data directories."
    }
    $debugDirectoryEntry = $dataDirectoryOffset + (6 * 8)
    if ($debugDirectoryEntry + 8 -gt $optionalHeaderEnd) {
        throw "PE optional header omits the debug data-directory entry."
    }
    $debugRva = [BitConverter]::ToUInt32($bytes, $debugDirectoryEntry)
    $debugSize = [BitConverter]::ToUInt32(
        $bytes,
        $debugDirectoryEntry + 4
    )
    if (($debugRva -eq 0) -ne ($debugSize -eq 0)) {
        throw "PE debug data-directory RVA/size pair is inconsistent."
    }

    $sectionTableOffset = $optionalHeaderEnd
    if ($sectionTableOffset + (40 * $sectionCount) -gt $bytes.Length) {
        throw "PE section table extends outside the file: $Path"
    }
    $sections = @(
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $sectionOffset = $sectionTableOffset + (40 * $index)
            [PSCustomObject]@{
                VirtualSize = [BitConverter]::ToUInt32(
                    $bytes,
                    $sectionOffset + 8
                )
                VirtualAddress = [BitConverter]::ToUInt32(
                    $bytes,
                    $sectionOffset + 12
                )
                RawSize = [BitConverter]::ToUInt32(
                    $bytes,
                    $sectionOffset + 16
                )
                RawPointer = [BitConverter]::ToUInt32(
                    $bytes,
                    $sectionOffset + 20
                )
            }
        }
    )
    Assert-PeSectionLayout `
        -Sections $sections `
        -FileLength $bytes.Length

    $sizeOfHeaders = [BitConverter]::ToUInt32(
        $bytes,
        $optionalHeaderOffset + 60
    )
    if ($sizeOfHeaders -gt [uint64]$bytes.Length) {
        throw "PE SizeOfHeaders extends outside the file: $Path"
    }
    $debugTypes = @()
    if ($debugSize -ne 0) {
        if (($debugSize % 28) -ne 0) {
            throw "PE debug directory is not a sequence of 28-byte entries."
        }
        $debugOffset = Convert-PeRvaToFileOffset `
            -Rva $debugRva `
            -Size $debugSize `
            -SizeOfHeaders $sizeOfHeaders `
            -Sections $sections `
            -FileLength $bytes.Length
        for (
            $entry = 0;
            $entry -lt ($debugSize / 28);
            $entry++
        ) {
            $entryOffset = $debugOffset + (28 * $entry)
            $debugTypes += [BitConverter]::ToUInt32(
                $bytes,
                $entryOffset + 12
            )
        }
    }

    [PSCustomObject]@{
        Bytes = $bytes
        Machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
        Magic = $magic
        Subsystem = [BitConverter]::ToUInt16(
            $bytes,
            $optionalHeaderOffset + 68
        )
        DebugDirectorySize = $debugSize
        DebugTypes = @($debugTypes)
    }
}

function Set-PeFixtureUInt16 {
    param(
        [Parameter(Mandatory = $true)] [byte[]] $Bytes,
        [Parameter(Mandatory = $true)] [int] $Offset,
        [Parameter(Mandatory = $true)] [uint16] $Value
    )

    ([BitConverter]::GetBytes($Value)).CopyTo($Bytes, $Offset)
}

function Set-PeFixtureUInt32 {
    param(
        [Parameter(Mandatory = $true)] [byte[]] $Bytes,
        [Parameter(Mandatory = $true)] [int] $Offset,
        [Parameter(Mandatory = $true)] [uint32] $Value
    )

    ([BitConverter]::GetBytes($Value)).CopyTo($Bytes, $Offset)
}

function New-PeParserFixture {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "ValidPe32Plus",
            "ValidPe32",
            "DirectoryCountTooSmall",
            "OverlappingSections",
            "NonAscendingSections",
            "RawOnlyDebug",
            "VirtualOnlyDebug",
            "AmbiguousHeaderSection"
        )]
        [string] $Kind
    )

    [byte[]]$bytes = New-Object byte[] 0x600
    $peOffset = 0x80
    $optionalHeaderOffset = $peOffset + 24
    $isPe32 = $Kind -eq "ValidPe32"
    $optionalHeaderSize = if ($isPe32) { 0xE0 } else { 0xF0 }
    $magic = if ($isPe32) { 0x010B } else { 0x020B }
    $numberOfRvaAndSizesOffset = if ($isPe32) { 92 } else { 108 }
    $dataDirectoryOffset = if ($isPe32) { 96 } else { 112 }
    $sectionCount = if (
        $Kind -eq "OverlappingSections" -or
        $Kind -eq "NonAscendingSections"
    ) {
        2
    }
    else {
        1
    }

    Set-PeFixtureUInt16 -Bytes $bytes -Offset 0 -Value 0x5A4D
    Set-PeFixtureUInt32 -Bytes $bytes -Offset 0x3C -Value $peOffset
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset $peOffset `
        -Value 0x00004550
    Set-PeFixtureUInt16 `
        -Bytes $bytes `
        -Offset ($peOffset + 4) `
        -Value 0xAA64
    Set-PeFixtureUInt16 `
        -Bytes $bytes `
        -Offset ($peOffset + 6) `
        -Value $sectionCount
    Set-PeFixtureUInt16 `
        -Bytes $bytes `
        -Offset ($peOffset + 20) `
        -Value $optionalHeaderSize
    Set-PeFixtureUInt16 `
        -Bytes $bytes `
        -Offset $optionalHeaderOffset `
        -Value $magic
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset ($optionalHeaderOffset + 60) `
        -Value 0x200
    Set-PeFixtureUInt16 `
        -Bytes $bytes `
        -Offset ($optionalHeaderOffset + 68) `
        -Value 2

    $directoryCount = if ($Kind -eq "DirectoryCountTooSmall") {
        6
    }
    else {
        16
    }
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset (
            $optionalHeaderOffset + $numberOfRvaAndSizesOffset
        ) `
        -Value $directoryCount

    $debugRva = switch ($Kind) {
        "RawOnlyDebug" { 0x1100 }
        "VirtualOnlyDebug" { 0x1100 }
        "AmbiguousHeaderSection" { 0x100 }
        default { 0x1000 }
    }
    $debugDirectoryEntry = (
        $optionalHeaderOffset + $dataDirectoryOffset + (6 * 8)
    )
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset $debugDirectoryEntry `
        -Value $debugRva
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset ($debugDirectoryEntry + 4) `
        -Value 28

    $sectionOffset = $optionalHeaderOffset + $optionalHeaderSize
    $virtualSize = switch ($Kind) {
        "RawOnlyDebug" { 0x80 }
        default { 0x200 }
    }
    $virtualAddress = if ($Kind -eq "AmbiguousHeaderSection") {
        0x100
    }
    else {
        0x1000
    }
    $rawSize = switch ($Kind) {
        "VirtualOnlyDebug" { 0x80 }
        "AmbiguousHeaderSection" { 0x100 }
        default { 0x200 }
    }
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset ($sectionOffset + 8) `
        -Value $virtualSize
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset ($sectionOffset + 12) `
        -Value $virtualAddress
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset ($sectionOffset + 16) `
        -Value $rawSize
    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset ($sectionOffset + 20) `
        -Value 0x200

    if ($sectionCount -eq 2) {
        $secondSectionOffset = $sectionOffset + 40
        $secondVirtualAddress = if (
            $Kind -eq "NonAscendingSections"
        ) {
            0x800
        }
        else {
            0x1100
        }
        Set-PeFixtureUInt32 `
            -Bytes $bytes `
            -Offset ($secondSectionOffset + 8) `
            -Value 0x100
        Set-PeFixtureUInt32 `
            -Bytes $bytes `
            -Offset ($secondSectionOffset + 12) `
            -Value $secondVirtualAddress
        Set-PeFixtureUInt32 `
            -Bytes $bytes `
            -Offset ($secondSectionOffset + 16) `
            -Value 0x100
        Set-PeFixtureUInt32 `
            -Bytes $bytes `
            -Offset ($secondSectionOffset + 20) `
            -Value 0x400
    }

    Set-PeFixtureUInt32 `
        -Bytes $bytes `
        -Offset 0x20C `
        -Value 16
    return ,$bytes
}

function Assert-PeFixtureRejected {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $ExpectedMessage
    )

    $failureMessage = $null
    try {
        Get-PeIdentity -Path $Path | Out-Null
    }
    catch {
        $failureMessage = $_.Exception.Message
    }
    if ($null -eq $failureMessage) {
        throw "Malformed PE fixture was unexpectedly accepted: $Path"
    }
    if (-not $failureMessage.Contains($ExpectedMessage)) {
        throw (
            "Malformed PE fixture failed for the wrong reason. Expected " +
            "'$ExpectedMessage'; observed '$failureMessage'."
        )
    }
}

function Test-PeParserMalformedFixtures {
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $caseName = "ebirforms-pe-parser-$PID-$([Guid]::NewGuid())"
    $caseRoot = [IO.Path]::GetFullPath(
        (Join-Path $temporaryRoot $caseName)
    )
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    try {
        foreach ($validKind in @("ValidPe32Plus", "ValidPe32")) {
            $path = Join-Path $caseRoot "$validKind.exe"
            [IO.File]::WriteAllBytes(
                $path,
                (New-PeParserFixture -Kind $validKind)
            )
            $identity = Get-PeIdentity -Path $path
            Assert-Equal $identity.DebugDirectorySize 28 (
                "$validKind debug-directory size"
            )
            Assert-Equal $identity.DebugTypes.Count 1 (
                "$validKind debug-directory entry count"
            )
            Assert-Equal $identity.DebugTypes[0] 16 (
                "$validKind debug-directory entry type"
            )
        }

        $rejections = @(
            [PSCustomObject]@{
                Kind = "DirectoryCountTooSmall"
                Message = "declares fewer than seven data directories"
            }
            [PSCustomObject]@{
                Kind = "OverlappingSections"
                Message = "section RVA ranges overlap"
            }
            [PSCustomObject]@{
                Kind = "NonAscendingSections"
                Message = "section RVAs are not strictly ascending"
            }
            [PSCustomObject]@{
                Kind = "RawOnlyDebug"
                Message = "both the virtual and raw-backed extent"
            }
            [PSCustomObject]@{
                Kind = "VirtualOnlyDebug"
                Message = "both the virtual and raw-backed extent"
            }
            [PSCustomObject]@{
                Kind = "AmbiguousHeaderSection"
                Message = "maps ambiguously to multiple file locations"
            }
        )
        foreach ($rejection in $rejections) {
            $path = Join-Path $caseRoot "$($rejection.Kind).exe"
            [IO.File]::WriteAllBytes(
                $path,
                (New-PeParserFixture -Kind $rejection.Kind)
            )
            Assert-PeFixtureRejected `
                -Path $path `
                -ExpectedMessage $rejection.Message
        }
    }
    finally {
        $resolvedCaseRoot = [IO.Path]::GetFullPath($caseRoot)
        $temporaryPrefix = $temporaryRoot.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ) + [IO.Path]::DirectorySeparatorChar
        if (
            -not $resolvedCaseRoot.StartsWith(
                $temporaryPrefix,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            -not ([IO.Path]::GetFileName($resolvedCaseRoot)).StartsWith(
                "ebirforms-pe-parser-",
                [StringComparison]::Ordinal
            )
        ) {
            throw "Refusing to remove an unexpected PE-parser test directory."
        }
        if (Test-Path -LiteralPath $resolvedCaseRoot) {
            Remove-Item -LiteralPath $resolvedCaseRoot -Recurse -Force
        }
    }
}

if ($RunPeParserSelfTests) {
    Test-PeParserMalformedFixtures
    Write-Host (
        "PE parser fixture tests passed for directory counts, section " +
        "layout, and unique RVA mapping."
    )
    return
}

foreach ($required in @($installedExe, $packagedExe, $manifestPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Windows package output is missing: $required"
    }
}

$installedItem = Get-Item -LiteralPath $installedExe
$packagedItem = Get-Item -LiteralPath $packagedExe
$installedHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $installedExe
).Hash
$packagedHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $packagedExe
).Hash

Assert-Equal $packagedItem.Length $installedItem.Length (
    "Packaged executable length"
)
Assert-Equal $packagedHash $installedHash (
    "Packaged executable SHA-256"
)

$pe = Get-PeIdentity -Path $packagedExe
Assert-Equal $pe.Machine 0xAA64 "PE machine"
Assert-Equal $pe.Magic 0x020B "PE optional-header magic"
Assert-Equal $pe.Subsystem 2 "PE subsystem"
$debugTypes = @($pe.DebugTypes)
if ($debugTypes -contains 2) {
    throw "PE debug directory contains a CodeView entry."
}
Assert-Equal $pe.DebugDirectorySize 28 "PE debug-directory size"
Assert-Equal $debugTypes.Count 1 "PE debug-directory entry count"
Assert-Equal $debugTypes[0] 16 "PE debug-directory entry type"

$signature = Get-AuthenticodeSignature -LiteralPath $packagedExe
Assert-Equal ([string]$signature.Status) "NotSigned" (
    "Authenticode status"
)

$loaderName = "WebView2Loader.dll"
$asciiImage = [Text.Encoding]::ASCII.GetString($pe.Bytes)
$utf16EvenLength = $pe.Bytes.Length - ($pe.Bytes.Length % 2)
$utf16EvenImage = [Text.Encoding]::Unicode.GetString(
    $pe.Bytes,
    0,
    $utf16EvenLength
)
$utf16OddLength = $pe.Bytes.Length - 1
$utf16OddLength -= $utf16OddLength % 2
$utf16OddImage = [Text.Encoding]::Unicode.GetString(
    $pe.Bytes,
    1,
    $utf16OddLength
)
$storageClassification = "development_only_plaintext_not_production"
if (
    -not $asciiImage.Contains($storageClassification) -and
    -not $utf16EvenImage.Contains($storageClassification) -and
    -not $utf16OddImage.Contains($storageClassification)
) {
    throw (
        "Packaged executable omits the visible development-storage " +
        "classification."
    )
}
if (
    $asciiImage.Contains($loaderName) -or
    $utf16EvenImage.Contains($loaderName) -or
    $utf16OddImage.Contains($loaderName)
) {
    throw "Packaged executable contains a WebView2Loader.dll reference."
}

$loaderFiles = @(
    Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
        Where-Object {
            $_.Name -ieq "WebView2Loader.dll"
        }
)
if ($loaderFiles.Count -ne 0) {
    throw "Windows package contains WebView2Loader.dll."
}
$pdbFiles = @(
    Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
        Where-Object {
            $_.Extension -ieq ".pdb"
        }
)
if ($pdbFiles.Count -ne 0) {
    throw "Windows package contains a PDB."
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath
$requiredManifestFragments = @(
    '.artifact = "windows"'
    '.target = "windows"'
    '.version = "0.1.0"'
    ".app_id = `"$BundleId`""
    ".executable = `"$AppName.exe`""
    '.optimize = "ReleaseFast"'
    '.web_engine = "system"'
    '.web_layer = "none (declared: .webview_layer = \"exclude\")"'
    '.signing = "none"'
    '.subsystem = "gui"'
    '.asset_count = 7'
    '"native_views"'
    '"gpu_surfaces"'
)
foreach ($fragment in $requiredManifestFragments) {
    if (-not $manifest.Contains($fragment)) {
        throw "Package manifest is missing: $fragment"
    }
}

$inventory = @(
    Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring(
                $packageRoot.Length
            ).TrimStart("\")
            $hash = (
                Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
            ).Hash.ToLowerInvariant()
            "{0}`t{1}`t{2}" -f $relative, $_.Length, $hash
        }
)
$inventoryHeader = @(
    "# Relative path`tBytes`tSHA-256"
    "# Unsigned Windows ARM64 verification artifact; not an installer."
)
Set-Content -LiteralPath $inventoryPath -Encoding utf8 -Value (
    $inventoryHeader + $inventory
)

Write-Host "Windows package verification passed."
Write-Host "Installed/package SHA-256: $($installedHash.ToLowerInvariant())"
Write-Host "Executable bytes:          $($installedItem.Length)"
Write-Host "PE:                        ARM64 / PE32+ / GUI"
Write-Host "PE debug directory:        REPRO only; no CodeView"
Write-Host "Authenticode:              NotSigned"
Write-Host "Storage classification:    $storageClassification"
Write-Host "Inventory:                 $inventoryPath"
