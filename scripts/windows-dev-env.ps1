$ErrorActionPreference = "Stop"

# Dot-source this file from PowerShell before running the Windows build:
#
#   Set-ExecutionPolicy -Scope Process Bypass
#   . .\scripts\windows-dev-env.ps1
#
# The first command is needed on hosts whose default policy blocks all local
# PowerShell scripts. It changes only the current PowerShell process.
#
# Native SDK 0.6.1's ARM64 CLI and Zig 0.16.0's ARM64 compiler both crash
# during non-trivial startup/build work on the audited Windows 11 ARM64 host.
# The verified x64 binaries run under Windows emulation and Zig cross-compiles
# the shipped application for the real aarch64-windows target.

$taskToolRoot = Join-Path $env:LOCALAPPDATA "eBIRForms\toolchains"
$nodeRoot = Join-Path $env:LOCALAPPDATA (
    "Microsoft\WinGet\Packages\" +
    "OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe\" +
    "node-v24.18.0-win-arm64"
)
$gitRoot = Join-Path $taskToolRoot "mingit-2.55.0.3-arm64"
$zigRoot = Join-Path $taskToolRoot "zig-x86_64-windows-0.16.0"
$nativeRoot = Join-Path $taskToolRoot "native-sdk-0.6.1-win32-x64"

$nodeExe = Join-Path $nodeRoot "node.exe"
$gitExe = Join-Path $gitRoot "cmd\git.exe"
$zigExe = Join-Path $zigRoot "zig.exe"
$nativeExe = Join-Path $nativeRoot "bin\native.exe"

foreach ($required in @($nodeExe, $gitExe, $zigExe, $nativeExe)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required Windows development tool is missing: $required"
    }
}

$expectedExecutableSha256 = @{
    $nodeExe = "C7225670C3F477778E18C43A55867F7A0D76468221245E5981AB80EB953C8102"
    $gitExe = "B05B2D7EB80933C602272B5DDF132ADF288CF78AD8E32A7A47CA7E200076B9F3"
    $zigExe = "086CE9D47BA42F33A514E1A6E04EB1D4A8FA1D75E0868E0213CAAD447C91E864"
    $nativeExe = "F92508DDF22141084139481AA0490EF56B37FBDE0F55B0FFCBD646C079571684"
}
foreach ($entry in $expectedExecutableSha256.GetEnumerator()) {
    $observed = (Get-FileHash -Algorithm SHA256 -LiteralPath $entry.Key).Hash
    if ($observed -ne $entry.Value) {
        throw "Tool hash mismatch: $($entry.Key)"
    }
}

$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..")
)
$sdkRoot = Join-Path $repositoryRoot "node_modules\@native-sdk\cli"
if (-not (Test-Path -LiteralPath (Join-Path $sdkRoot "src\root.zig"))) {
    throw "Native SDK source is missing. Run npm ci in $repositoryRoot."
}
$arm64CliPackage = Join-Path $repositoryRoot (
    "node_modules\@native-sdk\cli-win32-arm64\package.json"
)
if (-not (Test-Path -LiteralPath $arm64CliPackage)) {
    throw "The clean npm install did not select cli-win32-arm64."
}
$arm64CliMetadata = Get-Content -Raw -LiteralPath $arm64CliPackage |
    ConvertFrom-Json
if (
    $arm64CliMetadata.name -ne "@native-sdk/cli-win32-arm64" -or
    $arm64CliMetadata.version -ne "0.6.1"
) {
    throw "Unexpected Native SDK ARM64 package identity."
}

$env:PATH = @(
    $zigRoot
    (Join-Path $gitRoot "cmd")
    $nodeRoot
    $env:PATH
) -join ";"
$env:NATIVE_SDK_ZIG = $zigExe
$env:NATIVE_SDK_PATH = $sdkRoot
$env:EBIRFORMS_NATIVE_CLI = $nativeExe
$env:EBIRFORMS_WINDOWS_TARGET = "aarch64-windows"
$env:npm_config_cache = Join-Path $env:LOCALAPPDATA "eBIRForms\npm-cache"

# Zig cache writes on the mapped W: workspace failed atomic renames during
# the audited Windows build. Keep both cache layers on the local filesystem;
# use a worktree-specific local cache so the primary and build worktrees do
# not overwrite one another's build graph.
$cacheLeaf = Split-Path -Leaf $repositoryRoot
$cacheLeaf = $cacheLeaf -replace "[^A-Za-z0-9._-]", "_"
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $env:LOCALAPPDATA (
    "eBIRForms\zig-cache\global"
)
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $env:LOCALAPPDATA (
    "eBIRForms\zig-cache\local\$cacheLeaf"
)
foreach (
    $cacheDirectory in @(
        $env:npm_config_cache
        $env:ZIG_GLOBAL_CACHE_DIR
        $env:ZIG_LOCAL_CACHE_DIR
    )
) {
    if (-not (Test-Path -LiteralPath $cacheDirectory)) {
        New-Item -ItemType Directory -Path $cacheDirectory -Force |
            Out-Null
    }
}

$nodeIdentity = & $nodeExe -p (
    "process.version + ' ' + process.arch + ' ' + process.platform"
)
$gitIdentity = & $gitExe --version
$zigIdentity = & $zigExe version
$nativeIdentity = & $nativeExe version
if ($nodeIdentity -ne "v24.18.0 arm64 win32") {
    throw "Unexpected Node identity: $nodeIdentity"
}
if ($gitIdentity -ne "git version 2.55.0.windows.3") {
    throw "Unexpected Git identity: $gitIdentity"
}
if ($zigIdentity -ne "0.16.0") {
    throw "Unexpected Zig identity: $zigIdentity"
}
if (
    $nativeIdentity -ne
    "native 0.6.1 (commit a7509a7, automation protocol 0x096c8aa4730c11ec)"
) {
    throw "Unexpected Native CLI identity: $nativeIdentity"
}

Write-Host "Node:       $nodeIdentity"
Write-Host "Git:        $gitIdentity"
Write-Host "Zig host:   $zigIdentity (x64 emulation; target aarch64-windows)"
Write-Host "Native CLI: $nativeIdentity (x64 emulation)"
Write-Host "SDK source: $sdkRoot"
Write-Host "Zig global: $env:ZIG_GLOBAL_CACHE_DIR"
Write-Host "Zig local:  $env:ZIG_LOCAL_CACHE_DIR"
