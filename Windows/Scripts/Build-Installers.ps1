[CmdletBinding()]
param(
    [string]$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..")),
    [string]$InputRoot = "",
    [string]$OutputRoot = "",
    [string]$InnoCompilerPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($InputRoot)) {
    $InputRoot = Join-Path $RepositoryRoot ".build\artifacts"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepositoryRoot ".build\installers"
}

function Resolve-InnoCompiler {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Resolve-Path -LiteralPath $ExplicitPath).ProviderPath
    }

    $command = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
        (Join-Path $env:ProgramFiles "Inno Setup 7\ISCC.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 7\ISCC.exe")
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    throw "ISCC.exe was not found. Install Inno Setup 6.3 or later, or pass -InnoCompilerPath."
}

function Assert-PeArchitecture {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [ValidateSet("x64", "arm64")] [string]$Architecture
    )

    $expectedMachine = if ($Architecture -eq "x64") { 0x8664 } else { 0xaa64 }
    $stream = [System.IO.File]::OpenRead($Path)
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) {
            throw "The installer input is not a PE file: $Path"
        }
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 0x40 -or $peOffset -gt ($stream.Length - 6)) {
            throw "The installer input has an invalid PE header: $Path"
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            throw "The installer input has an invalid PE signature: $Path"
        }
        $actualMachine = $reader.ReadUInt16()
        if ($actualMachine -ne $expectedMachine) {
            throw ("The installer input architecture is wrong for {0}: {1} has PE machine 0x{2:x4}." -f `
                $Architecture,
                $Path,
                $actualMachine)
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function New-ThumbnailBundleId {
    param(
        [Parameter(Mandatory)] [string]$Directory,
        [Parameter(Mandatory)] [string]$AppVersion
    )

    $files = @(
        Get-ChildItem -LiteralPath $Directory -File -Recurse |
            Where-Object {
                $_.Name -ne ".bundlepack-provider-id" -and
                $_.Extension -ne ".pdb"
            } |
            Sort-Object FullName
    )
    if ($files.Count -eq 0) {
        throw "The thumbnail provider directory is empty: $Directory"
    }

    $fingerprintLines = foreach ($file in $files) {
        $relativePath = [System.IO.Path]::GetRelativePath($Directory, $file.FullName)
        $relativePath = $relativePath.Replace(
            [System.IO.Path]::DirectorySeparatorChar,
            [char]'/')
        $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $fileHash = $fileHash.ToLowerInvariant()
        "$relativePath=$fileHash"
    }
    $fingerprintText = $fingerprintLines -join "`n"
    $fingerprintBytes = [System.Text.Encoding]::UTF8.GetBytes($fingerprintText)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = [System.BitConverter]::ToString(
            $hasher.ComputeHash($fingerprintBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }

    return "v$AppVersion-$($fingerprint.Substring(0, 16))"
}

$compiler = Resolve-InnoCompiler -ExplicitPath $InnoCompilerPath
$propsPath = Join-Path $RepositoryRoot "Windows\Directory.Build.props"
[xml]$props = Get-Content -LiteralPath $propsPath -Raw
$appVersion = [string]$props.Project.PropertyGroup.VersionPrefix
if ([string]::IsNullOrWhiteSpace($appVersion)) {
    throw "VersionPrefix is missing from Windows\Directory.Build.props."
}

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$definitions = @(
    @{ Architecture = "x64"; Script = "BundlePack.x64.iss" },
    @{ Architecture = "arm64"; Script = "BundlePack.arm64.iss" }
)

foreach ($definition in $definitions) {
    $architecture = $definition.Architecture
    $sourceDirectory = Join-Path $InputRoot "BundlePack-Windows-$architecture"
    $scriptPath = Join-Path $RepositoryRoot "Windows\Installer\$($definition.Script)"
    $executablePath = Join-Path $sourceDirectory "BundlePack.Windows.exe"
    $thumbnailDirectory = Join-Path $sourceDirectory "ThumbnailProvider"
    $thumbnailPath = Join-Path $thumbnailDirectory "BundlePack.Thumbnail.comhost.dll"

    $requiredPaths = @(
        $scriptPath,
        $executablePath,
        (Join-Path $sourceDirectory "BundlePack.Windows.dll"),
        (Join-Path $sourceDirectory "BundlePack.Windows.deps.json"),
        (Join-Path $sourceDirectory "BundlePack.Windows.runtimeconfig.json"),
        $thumbnailPath,
        (Join-Path $sourceDirectory "ThumbnailProvider\BundlePack.Thumbnail.dll"),
        (Join-Path $sourceDirectory "ThumbnailProvider\BundlePack.Thumbnail.deps.json"),
        (Join-Path $sourceDirectory "ThumbnailProvider\BundlePack.Thumbnail.runtimeconfig.json")
    )
    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required installer input was not found: $requiredPath"
        }
    }
    Assert-PeArchitecture -Path $executablePath -Architecture $architecture
    Assert-PeArchitecture -Path $thumbnailPath -Architecture $architecture

    $thumbnailBundleId = New-ThumbnailBundleId `
        -Directory $thumbnailDirectory `
        -AppVersion $appVersion
    $thumbnailBundleMarker = Join-Path $thumbnailDirectory ".bundlepack-provider-id"
    $thumbnailBundleId | Set-Content -LiteralPath $thumbnailBundleMarker -Encoding ascii

    & $compiler `
        "/DSourceDir=$sourceDirectory" `
        "/DOutputDir=$OutputRoot" `
        "/DAppVersion=$appVersion" `
        "/DThumbnailBundleId=$thumbnailBundleId" `
        $scriptPath
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup failed for $architecture with exit code $LASTEXITCODE."
    }

    $installerPath = Join-Path $OutputRoot "BundlePack-Setup-$architecture.exe"
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf) -or
        (Get-Item -LiteralPath $installerPath).Length -eq 0) {
        throw "The $architecture installer was not created."
    }

    $hash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([System.IO.Path]::GetFileName($installerPath))" |
        Set-Content -LiteralPath "$installerPath.sha256" -Encoding ascii
}

Write-Host "BundlePack x64 and ARM64 installers were created in $OutputRoot."
