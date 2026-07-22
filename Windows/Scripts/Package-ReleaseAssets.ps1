[CmdletBinding()]
param(
    [string]$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")),
    [string]$ApplicationRoot = "",
    [string]$InstallerRoot = "",
    [string]$OutputRoot = "",
    [string]$Version = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApplicationRoot)) {
    $ApplicationRoot = Join-Path $RepositoryRoot ".build\artifacts"
}
if ([string]::IsNullOrWhiteSpace($InstallerRoot)) {
    $InstallerRoot = Join-Path $RepositoryRoot ".build\installers"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ".build\release-assets"
}

$propsPath = Join-Path $RepositoryRoot "Windows\Directory.Build.props"
[xml]$props = Get-Content -LiteralPath $propsPath -Raw
$projectVersion = [string]$props.Project.PropertyGroup.VersionPrefix
if ([string]::IsNullOrWhiteSpace($projectVersion)) {
    throw "VersionPrefix is missing from Windows\Directory.Build.props."
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $projectVersion
}
elseif ($Version -ne $projectVersion) {
    throw "Requested release version $Version does not match project version $projectVersion."
}
if ($Version.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw "Release version contains a character that is invalid in an asset name: $Version"
}

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

function Write-Sha256File {
    param([Parameter(Mandatory)] [string]$Path)

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileName = [System.IO.Path]::GetFileName($Path)
    "$hash  $fileName" | Set-Content -LiteralPath "$Path.sha256" -Encoding ascii
}

foreach ($architecture in @("x64", "arm64")) {
    $sourceDirectory = Join-Path $ApplicationRoot "BundlePack-Windows-$architecture"
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Windows $architecture application directory was not found: $sourceDirectory"
    }

    $archiveName = "BundlePack-Windows-$architecture-$Version.zip"
    $archivePath = Join-Path $OutputRoot $archiveName
    Compress-Archive `
        -LiteralPath $sourceDirectory `
        -DestinationPath $archivePath `
        -CompressionLevel Optimal
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf) -or
        (Get-Item -LiteralPath $archivePath).Length -eq 0) {
        throw "Windows $architecture application archive was not created."
    }
    Write-Sha256File -Path $archivePath
}

foreach ($architecture in @("x64", "arm64")) {
    $sourcePath = Join-Path $InstallerRoot "BundlePack-Setup-$architecture.exe"
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Windows $architecture installer was not found: $sourcePath"
    }

    $assetName = "BundlePack-Setup-$architecture-$Version.exe"
    $assetPath = Join-Path $OutputRoot $assetName
    Copy-Item -LiteralPath $sourcePath -Destination $assetPath
    Write-Sha256File -Path $assetPath
}

Write-Host "Versioned Windows release assets were created in $OutputRoot."
