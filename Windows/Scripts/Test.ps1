[CmdletBinding()]
param(
    [string]$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")),
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    [ValidateSet("x64", "ARM64")]
    [string]$Platform = "x64",
    [string]$FixturesDirectory = "",
    [string]$FixtureOutput = "",
    [switch]$CoreOnly,
    [switch]$SkipFileAssociation
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

function Find-BuildFile {
    param(
        [Parameter(Mandatory)] [string]$SearchRoot,
        [Parameter(Mandatory)] [string]$FileName,
        [Parameter(Mandatory)] [string]$Description
    )

    $item = Get-ChildItem `
        -LiteralPath $SearchRoot `
        -Filter $FileName `
        -File `
        -Recurse |
        Select-Object -First 1
    if ($null -eq $item) {
        throw "$Description was not found under $SearchRoot."
    }

    return $item
}

Get-Command dotnet -ErrorAction Stop | Out-Null

if ([string]::IsNullOrWhiteSpace($FixturesDirectory)) {
    $FixturesDirectory = Join-Path $RepositoryRoot "Fixtures\Compatibility\macOS"
}
if ([string]::IsNullOrWhiteSpace($FixtureOutput)) {
    $FixtureOutput = Join-Path $RepositoryRoot ".build\windows-fixtures"
}

$solution = Join-Path $RepositoryRoot "Windows\BundlePack.Windows.sln"
$coreTestsProject = Join-Path $RepositoryRoot "Windows\BundlePack.Core.Tests\BundlePack.Core.Tests.csproj"
$thumbnailTestsProject = Join-Path $RepositoryRoot "Windows\BundlePack.Thumbnail.Tests\BundlePack.Thumbnail.Tests.csproj"

if (Test-Path -LiteralPath $FixtureOutput) {
    Remove-Item -LiteralPath $FixtureOutput -Recurse -Force
}

$restoreTarget = $solution
$restoreOptions = @("-p:Platform=$Platform")
if ($CoreOnly) {
    $restoreTarget = $coreTestsProject
    $restoreOptions = @()
}

Invoke-DotNet -Arguments (@(
    "restore",
    $restoreTarget,
    "--locked-mode",
    "-p:NuGetAudit=true",
    "-p:NuGetAuditMode=all"
) + $restoreOptions)
Invoke-DotNet -Arguments @(
    "build",
    $coreTestsProject,
    "-c",
    $Configuration,
    "--no-restore"
)
Invoke-DotNet -Arguments @(
    "run",
    "--project",
    $coreTestsProject,
    "-c",
    $Configuration,
    "--no-build",
    "--no-restore",
    "--",
    "--repo",
    $RepositoryRoot,
    "--fixtures",
    $FixturesDirectory,
    "--output",
    $FixtureOutput
)

if ($CoreOnly) {
    Write-Host "All BundlePack Windows core tests passed."
    return
}

& (Join-Path $PSScriptRoot "Build.ps1") `
    -RepositoryRoot $RepositoryRoot `
    -Configuration $Configuration `
    -Platforms $Platform `
    -SkipRestore

Invoke-DotNet -Arguments @(
    "run",
    "--project",
    $thumbnailTestsProject,
    "-c",
    $Configuration,
    "-p:Platform=$Platform",
    "--no-restore",
    "--",
    "--fixtures",
    $FixtureOutput,
    "--fixtures",
    $FixturesDirectory
)

if (-not $SkipFileAssociation) {
    $appExecutable = Find-BuildFile `
        -SearchRoot (Join-Path $RepositoryRoot "Windows\BundlePack.Windows\bin\$Platform\$Configuration") `
        -FileName "BundlePack.Windows.exe" `
        -Description "The $Platform BundlePack executable"
    $thumbnailProvider = Find-BuildFile `
        -SearchRoot (Join-Path $RepositoryRoot "Windows\BundlePack.Thumbnail\bin\$Platform\$Configuration") `
        -FileName "BundlePack.Thumbnail.comhost.dll" `
        -Description "The $Platform thumbnail provider"

    & (Join-Path $RepositoryRoot "Windows\Tests\Test-FileAssociation.ps1") `
        -ExecutablePath $appExecutable.FullName `
        -ThumbnailProviderPath $thumbnailProvider.FullName
}

Write-Host "All BundlePack Windows tests passed for $Platform."
