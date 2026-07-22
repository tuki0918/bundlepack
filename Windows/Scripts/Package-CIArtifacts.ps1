[CmdletBinding()]
param(
    [string]$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")),
    [string]$OutputRoot = "",
    [ValidateSet("x64", "ARM64")]
    [string[]]$Platforms = @("x64", "ARM64")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ".build\artifacts"
}

function Find-BuildFile {
    param(
        [Parameter(Mandatory)]
        [string]$SearchRoot,
        [Parameter(Mandatory)]
        [string]$FileName,
        [Parameter(Mandatory)]
        [string]$Description
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

foreach ($platform in $Platforms) {
    $appExecutable = Find-BuildFile `
        -SearchRoot (Join-Path $RepositoryRoot "Windows\BundlePack.Windows\bin\$platform\Release") `
        -FileName "BundlePack.Windows.exe" `
        -Description "The $platform BundlePack executable"
    $thumbnailProvider = Find-BuildFile `
        -SearchRoot (Join-Path $RepositoryRoot "Windows\BundlePack.Thumbnail\bin\$platform\Release") `
        -FileName "BundlePack.Thumbnail.comhost.dll" `
        -Description "The $platform thumbnail provider"

    $architecture = $platform.ToLowerInvariant()
    $artifactRoot = Join-Path $OutputRoot "BundlePack-Windows-$architecture"
    $thumbnailRoot = Join-Path $artifactRoot "ThumbnailProvider"
    if (Test-Path -LiteralPath $artifactRoot) {
        Remove-Item -LiteralPath $artifactRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $thumbnailRoot -Force | Out-Null

    foreach ($item in Get-ChildItem -LiteralPath $appExecutable.Directory.FullName -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $artifactRoot -Recurse -Force
    }
    foreach ($item in Get-ChildItem -LiteralPath $thumbnailProvider.Directory.FullName -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $thumbnailRoot -Recurse -Force
    }

    Copy-Item -LiteralPath @(
        (Join-Path $RepositoryRoot "Windows\Scripts\Register-FileAssociation.ps1")
        (Join-Path $RepositoryRoot "Windows\Scripts\Unregister-FileAssociation.ps1")
    ) -Destination $artifactRoot -Force

    @(
        "BundlePack CI test build for Windows $platform."
        ""
        "Run BundlePack.Windows.exe from this directory."
        "This build is unpackaged and unsigned; use it only for testing."
        "Install the matching .NET 10 and Windows App Runtime prerequisites if Windows reports that a runtime is missing."
        "Keep the ThumbnailProvider directory together if you register Explorer thumbnails."
        ""
        "Optional current-user registration:"
        "  .\Register-FileAssociation.ps1 -ExecutablePath .\BundlePack.Windows.exe -ThumbnailProviderPath .\ThumbnailProvider\BundlePack.Thumbnail.comhost.dll"
        ""
        "Remove the registration with:"
        "  .\Unregister-FileAssociation.ps1"
    ) | Set-Content -LiteralPath (Join-Path $artifactRoot "README.txt") -Encoding utf8

    if (-not (Test-Path -LiteralPath (Join-Path $artifactRoot "BundlePack.Windows.exe"))) {
        throw "The $platform application artifact is incomplete."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $thumbnailRoot "BundlePack.Thumbnail.comhost.dll"))) {
        throw "The $platform thumbnail artifact is incomplete."
    }
}
