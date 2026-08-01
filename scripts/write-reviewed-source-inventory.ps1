param(
    [string]$RepositoryRoot = [IO.Path]::GetFullPath(
        (Join-Path $PSScriptRoot "..")
    ),
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Repository root does not exist: $root"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root (
        "zig-out\package\reviewed-source-inventory.txt"
    )
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $root $OutputPath
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$topLevelFiles = @(
    "app.zon"
    "build.zig"
    "build.zig.zon"
    "package.json"
    "package-lock.json"
    "README.md"
)
$sourceDirectories = @(
    "assets"
    "scripts"
    "src"
)

$files = [Collections.Generic.List[IO.FileInfo]]::new()
foreach ($relative in $topLevelFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Reviewed source file is missing: $path"
    }
    $files.Add((Get-Item -LiteralPath $path))
}
foreach ($relative in $sourceDirectories) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Reviewed source directory is missing: $path"
    }
    foreach ($item in Get-ChildItem -LiteralPath $path -Recurse -File) {
        $files.Add($item)
    }
}

$rows = @(
    $files |
        Sort-Object FullName -Unique |
        ForEach-Object {
            $relative = $_.FullName.Substring($root.Length).TrimStart(
                [IO.Path]::DirectorySeparatorChar,
                [IO.Path]::AltDirectorySeparatorChar
            )
            $hash = (
                Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
            ).Hash.ToLowerInvariant()
            "{0}`t{1}`t{2}" -f $relative, $_.Length, $hash
        }
)

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
Set-Content -LiteralPath $OutputPath -Encoding utf8 -Value (
    @(
        "# Relative path`tBytes`tSHA-256"
        "# Reviewed build/runtime/test source; excludes data and artifacts."
    ) + $rows
)

$inventoryHash = (
    Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
).Hash.ToLowerInvariant()
Write-Host "Reviewed source inventory written."
Write-Host "Files:     $($rows.Count)"
Write-Host "SHA-256:   $inventoryHash"
Write-Host "Inventory: $OutputPath"
