[CmdletBinding()]
param(
    [string]$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")),
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [ValidateSet("x64", "ARM64")]
    [string[]]$Platforms = @("x64", "ARM64"),
    [switch]$SkipRestore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-DotNet {
    param([Parameter(Mandatory)] [string[]]$Arguments)

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

Get-Command dotnet -ErrorAction Stop | Out-Null

$solution = Join-Path $RepositoryRoot "Windows\BundlePack.Windows.sln"
$appProject = Join-Path $RepositoryRoot "Windows\BundlePack.Windows\BundlePack.Windows.csproj"
$thumbnailProject = Join-Path $RepositoryRoot "Windows\BundlePack.Thumbnail\BundlePack.Thumbnail.csproj"

foreach ($platform in $Platforms) {
    if (-not $SkipRestore) {
        Invoke-DotNet -Arguments @(
            "restore",
            $solution,
            "--locked-mode",
            "-p:NuGetAudit=true",
            "-p:NuGetAuditMode=all",
            "-p:Platform=$platform"
        )
    }

    $buildOptions = @("-c", $Configuration, "-p:Platform=$platform")
    if ($SkipRestore) {
        $buildOptions += "--no-restore"
    }

    Invoke-DotNet -Arguments (@("build", $appProject) + $buildOptions)
    Invoke-DotNet -Arguments (@("build", $thumbnailProject) + $buildOptions)
}

Write-Host "BundlePack Windows builds completed for $($Platforms -join ', ')."
