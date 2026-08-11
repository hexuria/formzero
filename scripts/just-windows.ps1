param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet(
        "setup",
        "check",
        "test",
        "build",
        "build-automation",
        "run",
        "doctor",
        "package",
        "app",
        "install"
    )]
    [string]$Command
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot "..")
)
Set-Location -LiteralPath $repositoryRoot

$identityJson = & node scripts/app-identity.mjs prepare --format json
if ($LASTEXITCODE -ne 0) {
    throw "Failed to resolve Buwiz app identity."
}
$appIdentity = $identityJson | ConvertFrom-Json
$appName = [string]$appIdentity.appName
$displayName = [string]$appIdentity.displayName
$bundleId = [string]$appIdentity.bundleId
$manifestPath = [string]$appIdentity.manifestPath
$packageRelativePath = "zig-out\package\$appName-windows"
$resolvedPackageRoot = Join-Path $repositoryRoot $packageRelativePath

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Executable,
        [Parameter(Position = 1)]
        [string[]]$Arguments = @()
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Executable"
    }
}

function Invoke-NativeCli {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$Arguments
    )

    if ([string]::IsNullOrWhiteSpace($env:BUWIZ_NATIVE_CLI)) {
        Invoke-Checked "npx.cmd" (@("native") + $Arguments)
        return
    }

    Invoke-Checked $env:BUWIZ_NATIVE_CLI $Arguments
}

function Require-TargetEnvironment {
    if ([string]::IsNullOrWhiteSpace($env:NATIVE_SDK_ZIG)) {
        throw (
            "NATIVE_SDK_ZIG is not set. In the same PowerShell session, " +
            "dot-source scripts/windows-dev-env.ps1 before running this command."
        )
    }
    if ([string]::IsNullOrWhiteSpace($env:BUWIZ_WINDOWS_TARGET)) {
        throw (
            "BUWIZ_WINDOWS_TARGET is not set. In the same PowerShell " +
            "session, dot-source scripts/windows-dev-env.ps1 first."
        )
    }
}

function Invoke-TargetZig {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]]$Arguments
    )

    Require-TargetEnvironment
    Invoke-Checked $env:NATIVE_SDK_ZIG $Arguments
}

switch ($Command) {
    "setup" {
        Invoke-Checked "npm.cmd" @("ci")
        Write-Host "Locked npm dependencies installed."
        Write-Host (
            "Load the pinned Windows toolchain in this PowerShell session with: " +
            ". .\scripts\windows-dev-env.ps1"
        )
    }

    "check" {
        Invoke-Checked "npm.cmd" @("run", "test:app-identity")
        Invoke-Checked "npm.cmd" @("run", "check:tax-catalog")
        Invoke-Checked "node" @("scripts/patch-native-sdk-combobox-tab.mjs")
        Invoke-NativeCli @("doctor", "--manifest", $manifestPath, "--strict")
    }

    "test" {
        Invoke-Checked "node" @("scripts/patch-native-sdk-combobox-tab.mjs")
        Invoke-NativeCli @("test", ".", "--yes", "-Dplatform=null")
    }

    "build" {
        Invoke-Checked "node" @("scripts/patch-native-sdk-combobox-tab.mjs")
        Invoke-TargetZig @(
            "build",
            "-Dtarget=$env:BUWIZ_WINDOWS_TARGET",
            "-Doptimize=ReleaseFast"
        )
    }

    "build-automation" {
        Invoke-Checked "node" @("scripts/patch-native-sdk-combobox-tab.mjs")
        Invoke-TargetZig @(
            "build",
            "-Dtarget=$env:BUWIZ_WINDOWS_TARGET",
            "-Doptimize=ReleaseFast",
            "-Dautomation=true"
        )
    }

    "run" {
        Require-TargetEnvironment
        Invoke-Checked "node" @("scripts/patch-native-sdk-combobox-tab.mjs")
        Invoke-NativeCli @(
            "dev",
            ".",
            "--yes",
            "-Dtarget=$env:BUWIZ_WINDOWS_TARGET"
        )
    }

    "doctor" {
        Invoke-NativeCli @("doctor", "--manifest", $manifestPath, "--strict")
    }

    "package" {
        Require-TargetEnvironment

        if (Test-Path -LiteralPath $resolvedPackageRoot) {
            $backup = "$resolvedPackageRoot.previous.$(Get-Date -Format yyyyMMdd-HHmmss)"
            Move-Item -LiteralPath $resolvedPackageRoot -Destination $backup
            Write-Host "Moved previous package to $backup"
        }

        Invoke-NativeCli @(
            "package",
            "--target",
            "windows",
            "--manifest",
            $manifestPath,
            "--output",
            $packageRelativePath,
            "--binary",
            "zig-out\bin\$appName.exe",
            "--optimize",
            "ReleaseFast",
            "--web-layer",
            "exclude",
            "--web-engine",
            "system",
            "--signing",
            "none",
            "--assets",
            "assets"
        )

        $verifier = Join-Path $PSScriptRoot "verify-windows-package.ps1"
        Invoke-Checked "powershell.exe" @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $verifier,
            "-RepositoryRoot",
            $repositoryRoot,
            "-AppName",
            $appName,
            "-BundleId",
            $bundleId
        )
    }

    "app" {
        $packagedExe = Join-Path $resolvedPackageRoot "bin\$appName.exe"
        if (-not (Test-Path -LiteralPath $packagedExe -PathType Leaf)) {
            throw "Packaged Windows executable is missing: $packagedExe"
        }
        Start-Process -FilePath $packagedExe | Out-Null
        Write-Host "Launched $packagedExe"
    }

    "install" {
        if (-not (Test-Path -LiteralPath $resolvedPackageRoot -PathType Container)) {
            throw "Windows package directory is missing: $resolvedPackageRoot"
        }

        $parentDirectory = if (
            [string]::IsNullOrWhiteSpace($env:BUWIZ_INSTALL_DIR)
        ) {
            Join-Path $env:LOCALAPPDATA "Programs"
        } else {
            $env:BUWIZ_INSTALL_DIR
        }
        $targetDirectory = Join-Path $parentDirectory $displayName
        New-Item -ItemType Directory -Force -Path $parentDirectory | Out-Null

        if (Test-Path -LiteralPath $targetDirectory) {
            $backup = "$targetDirectory.previous.$(Get-Date -Format yyyyMMdd-HHmmss)"
            Move-Item -LiteralPath $targetDirectory -Destination $backup
            Write-Host "Moved previous install to $backup"
        }

        New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
        Get-ChildItem -LiteralPath $resolvedPackageRoot -Force |
            Copy-Item -Destination $targetDirectory -Recurse -Force
        $installedExe = Join-Path $targetDirectory "bin\$appName.exe"
        if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
            throw "Installed Windows executable is missing: $installedExe"
        }
        $startMenuDirectory = Join-Path $env:APPDATA (
            "Microsoft\Windows\Start Menu\Programs"
        )
        New-Item -ItemType Directory -Force -Path $startMenuDirectory |
            Out-Null
        $shortcutPath = Join-Path $startMenuDirectory "$displayName.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $installedExe
        $shortcut.WorkingDirectory = Split-Path -Parent $installedExe
        $shortcut.IconLocation = "$installedExe,0"
        $shortcut.Save()
        Write-Host "Installed $targetDirectory"
        Write-Host "Start Menu shortcut: $shortcutPath"
    }
}
