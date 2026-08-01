param(
    [Parameter(Mandatory = $true)]
    [string]$ZigExecutable,
    [string]$RepositoryRoot
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "..")
    )
}

$expectedReason = (
    "production-release unavailable: authenticated backend, operating-system " +
    "custody, recovery, legacy transition, and release qualification remain " +
    "unapproved"
)

if (-not (Test-Path -LiteralPath $ZigExecutable -PathType Leaf)) {
    throw "Zig executable is missing: $ZigExecutable"
}

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$caseName = "ebirforms-production-release-gate-$PID-$([Guid]::NewGuid())"
$caseRoot = [IO.Path]::GetFullPath((Join-Path $temporaryRoot $caseName))
$optionPrefix = Join-Path $caseRoot "option-prefix"
$ambiguousPrefix = Join-Path $caseRoot "ambiguous-prefix"
$cache = Join-Path $env:LOCALAPPDATA (
    "eBIRForms\zig-cache\production-release-gate-regression"
)
$globalCache = Join-Path $env:LOCALAPPDATA "eBIRForms\zig-cache\global"
$locationPushed = $false

function Invoke-ZigBuildCase {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(
            & $ZigExecutable @Arguments 2>&1 |
                ForEach-Object { [string]$_ }
        )
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }

    [PSCustomObject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Assert-NoPrefixFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $producedFiles = @()
    if (Test-Path -LiteralPath $Path) {
        $producedFiles = @(
            Get-ChildItem -LiteralPath $Path -File -Recurse
        )
    }
    if ($producedFiles.Count -ne 0) {
        throw "$Label produced install-prefix files."
    }
}

New-Item -ItemType Directory -Path $caseRoot | Out-Null
foreach ($cacheDirectory in @($cache, $globalCache)) {
    if (-not (Test-Path -LiteralPath $cacheDirectory)) {
        New-Item -ItemType Directory -Path $cacheDirectory -Force |
            Out-Null
    }
}
try {
    Push-Location -LiteralPath $RepositoryRoot
    $locationPushed = $true

    $optionResult = Invoke-ZigBuildCase -Arguments @(
        "build"
        "-Dproduction-release=true"
        "--prefix"
        $optionPrefix
        "--cache-dir"
        $cache
        "--global-cache-dir"
        $globalCache
    )
    $ambiguousResult = Invoke-ZigBuildCase -Arguments @(
        "build"
        "production-release"
        "install"
        "--prefix"
        $ambiguousPrefix
        "--cache-dir"
        $cache
        "--global-cache-dir"
        $globalCache
    )

    Pop-Location
    $locationPushed = $false

    if ($optionResult.ExitCode -eq 0) {
        throw "Production-release negative build unexpectedly succeeded."
    }
    $optionOutput = $optionResult.Output -join [Environment]::NewLine
    if (-not $optionOutput.Contains($expectedReason)) {
        throw (
            "Production-release failure omitted the source-pinned reason." +
            [Environment]::NewLine +
            $optionOutput
        )
    }
    Assert-NoPrefixFiles `
        -Path $optionPrefix `
        -Label "Production-release option failure"

    if ($ambiguousResult.ExitCode -eq 0) {
        throw "Ambiguous production-release build unexpectedly succeeded."
    }
    $ambiguousOutput = (
        $ambiguousResult.Output -join [Environment]::NewLine
    )
    if (
        -not $ambiguousOutput.Contains("production-release") -or
        (
            -not $ambiguousOutput.Contains("invalid top-level step") -and
            -not $ambiguousOutput.Contains("unknown") -and
            -not $ambiguousOutput.Contains("no step named")
        )
    ) {
        throw (
            "Ambiguous production-release build was not rejected as an " +
            "unknown top-level step." +
            [Environment]::NewLine +
            $ambiguousOutput
        )
    }
    Assert-NoPrefixFiles `
        -Path $ambiguousPrefix `
        -Label "Ambiguous production-release build"

    Write-Host (
        "Production-release option failed closed before artifact output."
    )
    Write-Host (
        "The unregistered production-release step was rejected before " +
        "the combined install request emitted output."
    )
    Write-Host $expectedReason
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
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
            "ebirforms-production-release-gate-",
            [StringComparison]::Ordinal
        )
    ) {
        throw "Refusing to remove an unexpected gate-test directory."
    }
    if (Test-Path -LiteralPath $resolvedCaseRoot) {
        Remove-Item -LiteralPath $resolvedCaseRoot -Recurse -Force
    }
}
