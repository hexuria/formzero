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

    if ([string]::IsNullOrWhiteSpace($env:EBIRFORMS_NATIVE_CLI)) {
        Invoke-Checked "npx.cmd" (@("native") + $Arguments)
        return
    }

    Invoke-Checked $env:EBIRFORMS_NATIVE_CLI $Arguments
}

function Require-TargetEnvironment {
    if ([string]::IsNullOrWhiteSpace($env:NATIVE_SDK_ZIG)) {
        throw (
            "NATIVE_SDK_ZIG is not set. In the same PowerShell session, " +
            "dot-source scripts/windows-dev-env.ps1 before running this command."
        )
    }
    if ([string]::IsNullOrWhiteSpace($env:EBIRFORMS_WINDOWS_TARGET)) {
        throw (
            "EBIRFORMS_WINDOWS_TARGET is not set. In the same PowerShell " +
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
        Invoke-Checked "npm.cmd" @("run", "check:tax-catalog")
        Invoke-NativeCli @("check", ".", "--strict")
    }

    "test" {
        Invoke-NativeCli @("test", ".", "--yes", "-Dplatform=null")
    }

    "build" {
        Invoke-TargetZig @(
            "build",
            "-Dtarget=$env:EBIRFORMS_WINDOWS_TARGET",
            "-Doptimize=ReleaseFast"
        )
    }

    "build-automation" {
        Invoke-TargetZig @(
            "build",
            "-Dtarget=$env:EBIRFORMS_WINDOWS_TARGET",
            "-Doptimize=ReleaseFast",
            "-Dautomation=true"
        )
    }

    "run" {
        Require-TargetEnvironment
        Invoke-NativeCli @(
            "dev",
            ".",
            "--yes",
            "-Dtarget=$env:EBIRFORMS_WINDOWS_TARGET"
        )
    }

    "doctor" {
        Invoke-NativeCli @("doctor", "--manifest", "app.zon", "--strict")
    }

    "package" {
        Require-TargetEnvironment

        $packageRoot = Join-Path $repositoryRoot "zig-out\package\windows"
        if (Test-Path -LiteralPath $packageRoot) {
            $backup = "$packageRoot.previous.$(Get-Date -Format yyyyMMdd-HHmmss)"
            Move-Item -LiteralPath $packageRoot -Destination $backup
            Write-Host "Moved previous package to $backup"
        }

        Invoke-NativeCli @(
            "package",
            "--target",
            "windows",
            "--manifest",
            "app.zon",
            "--output",
            "zig-out\package\windows",
            "--binary",
            "zig-out\bin\ebirforms-zero.exe",
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
            $repositoryRoot
        )
    }

    "app" {
        $packagedExe = Join-Path (
            Join-Path $repositoryRoot "zig-out\package\windows"
        ) "bin\ebirforms-zero.exe"
        if (-not (Test-Path -LiteralPath $packagedExe -PathType Leaf)) {
            throw "Packaged Windows executable is missing: $packagedExe"
        }
        Start-Process -FilePath $packagedExe | Out-Null
        Write-Host "Launched $packagedExe"
    }

    "install" {
        $packageRoot = Join-Path $repositoryRoot "zig-out\package\windows"
        if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
            throw "Windows package directory is missing: $packageRoot"
        }

        $parentDirectory = if (
            [string]::IsNullOrWhiteSpace($env:EBIRFORMS_INSTALL_DIR)
        ) {
            Join-Path $env:LOCALAPPDATA "Programs"
        } else {
            $env:EBIRFORMS_INSTALL_DIR
        }
        $targetDirectory = Join-Path $parentDirectory "eBIRForms"
        New-Item -ItemType Directory -Force -Path $parentDirectory | Out-Null

        if (Test-Path -LiteralPath $targetDirectory) {
            $backup = "$targetDirectory.previous.$(Get-Date -Format yyyyMMdd-HHmmss)"
            Move-Item -LiteralPath $targetDirectory -Destination $backup
            Write-Host "Moved previous install to $backup"
        }

        New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
        Get-ChildItem -LiteralPath $packageRoot -Force |
            Copy-Item -Destination $targetDirectory -Recurse -Force
        $installedExe = Join-Path $targetDirectory "bin\ebirforms-zero.exe"
        if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
            throw "Installed Windows executable is missing: $installedExe"
        }
        Write-Host "Installed $targetDirectory"
    }
}
