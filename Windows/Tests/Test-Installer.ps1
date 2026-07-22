[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,
    [string]$InstallRoot = (Join-Path $env:TEMP "BundlePack-Installer-Test")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedInstaller = (Resolve-Path -LiteralPath $InstallerPath).ProviderPath
$resolvedInstallRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$classesRoot = "HKCU:\Software\Classes"
$progIdPath = "$classesRoot\BundlePack.Archive.1"
$applicationPath = "$classesRoot\Applications\BundlePack.Windows.exe"
$openWithPath = "$classesRoot\.bundlepack\OpenWithProgids"
$capabilitiesPath = "HKCU:\Software\BundlePack\Capabilities"
$bundlePackRegistryPath = "HKCU:\Software\BundlePack"
$registrationPath = "HKCU:\Software\BundlePack\Registration"
$registeredApplicationsPath = "HKCU:\Software\RegisteredApplications"
$thumbnailClassId = "{645A25AB-1F31-4147-A47B-46E8515BF79D}"
$thumbnailHandlerId = "{E357FCCD-A995-4576-B01F-234630154E96}"
$thumbnailClassPath = "$classesRoot\CLSID\$thumbnailClassId"
$thumbnailHandlerPath = "$classesRoot\.bundlepack\shellex\$thumbnailHandlerId"
$approvedExtensionsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)] [string]$FilePath,
        [Parameter(Mandatory = $true)] [string[]]$Arguments
    )

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "$FilePath failed with exit code $($process.ExitCode)."
    }
}

function Get-RequiredRegistryValue {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "The expected registry key does not exist: $Path"
    }
    $key = Get-Item -LiteralPath $Path
    try {
        if ($key.GetValueNames() -notcontains $Name) {
            throw "The expected registry value does not exist: $Path [$Name]"
        }
        return [string]$key.GetValue(
            $Name,
            $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    finally {
        $key.Dispose()
    }
}

function Assert-RegistryValue {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$Name,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$ExpectedValue
    )

    $actualValue = Get-RequiredRegistryValue -Path $Path -Name $Name
    if ($actualValue -cne $ExpectedValue) {
        throw "Unexpected registry value at $Path [$Name]. Expected '$ExpectedValue', found '$actualValue'."
    }
}

function Assert-RegistryValueAbsent {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $key = Get-Item -LiteralPath $Path
    try {
        if ($key.GetValueNames() -contains $Name) {
            throw "The registry value was not removed: $Path [$Name]"
        }
    }
    finally {
        $key.Dispose()
    }
}

if (Test-Path -LiteralPath $resolvedInstallRoot) {
    throw "The installer test directory already exists: $resolvedInstallRoot"
}
foreach ($existingPath in @(
    $bundlePackRegistryPath,
    $progIdPath,
    $applicationPath,
    $capabilitiesPath,
    $registrationPath,
    $thumbnailClassPath,
    $thumbnailHandlerPath
)) {
    if (Test-Path -LiteralPath $existingPath) {
        throw "The installer test requires a clean BundlePack registration: $existingPath"
    }
}
Assert-RegistryValueAbsent -Path $openWithPath -Name "BundlePack.Archive.1"
Assert-RegistryValueAbsent -Path $registeredApplicationsPath -Name "BundlePack"
Assert-RegistryValueAbsent -Path $approvedExtensionsPath -Name $thumbnailClassId

$executablePath = Join-Path $resolvedInstallRoot "BundlePack.Windows.exe"
$thumbnailProviderRoot = Join-Path $resolvedInstallRoot "ThumbnailProvider"
$uninstallerPath = Join-Path $resolvedInstallRoot "unins000.exe"
$installAttempted = $false

try {
    $installAttempted = $true
    Invoke-CheckedProcess -FilePath $resolvedInstaller -Arguments @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-",
        "/DIR=`"$resolvedInstallRoot`""
    )
    foreach ($installedFile in @($executablePath, $uninstallerPath)) {
        if (-not (Test-Path -LiteralPath $installedFile -PathType Leaf)) {
            throw "The installer did not create the expected file: $installedFile"
        }
    }
    $thumbnailProviders = @(
        Get-ChildItem `
            -LiteralPath $thumbnailProviderRoot `
            -Filter "BundlePack.Thumbnail.comhost.dll" `
            -File `
            -Recurse
    )
    if ($thumbnailProviders.Count -ne 1) {
        throw "The installer must create exactly one versioned thumbnail provider directory."
    }
    $thumbnailProviderPath = $thumbnailProviders[0].FullName
    $thumbnailBundleMarker = Join-Path $thumbnailProviders[0].Directory.FullName ".bundlepack-provider-id"
    if (-not (Test-Path -LiteralPath $thumbnailBundleMarker -PathType Leaf)) {
        throw "The installed thumbnail provider is missing its content identifier."
    }

    $openCommand = "`"$executablePath`" `"%1`""
    Assert-RegistryValue -Path $progIdPath -Name "" -ExpectedValue "BundlePack Archive"
    Assert-RegistryValue -Path "$progIdPath\shell\open\command" -Name "" -ExpectedValue $openCommand
    Assert-RegistryValue -Path $openWithPath -Name "BundlePack.Archive.1" -ExpectedValue ""
    Assert-RegistryValue -Path $applicationPath -Name "FriendlyAppName" -ExpectedValue "BundlePack"
    Assert-RegistryValue -Path "$applicationPath\SupportedTypes" -Name ".bundlepack" -ExpectedValue ""
    Assert-RegistryValue -Path $capabilitiesPath -Name "ApplicationName" -ExpectedValue "BundlePack"
    Assert-RegistryValue -Path "$capabilitiesPath\FileAssociations" -Name ".bundlepack" -ExpectedValue "BundlePack.Archive.1"
    Assert-RegistryValue -Path $registeredApplicationsPath -Name "BundlePack" -ExpectedValue "Software\BundlePack\Capabilities"
    Assert-RegistryValue -Path $thumbnailClassPath -Name "" -ExpectedValue "BundlePack Thumbnail Provider"
    Assert-RegistryValue -Path "$thumbnailClassPath\InprocServer32" -Name "" -ExpectedValue $thumbnailProviderPath
    Assert-RegistryValue -Path $thumbnailHandlerPath -Name "" -ExpectedValue $thumbnailClassId
    Assert-RegistryValue -Path $approvedExtensionsPath -Name $thumbnailClassId -ExpectedValue "BundlePack Thumbnail Provider"
    Assert-RegistryValue -Path $registrationPath -Name "ExecutablePath" -ExpectedValue $executablePath
    Assert-RegistryValue -Path $registrationPath -Name "ThumbnailProviderPath" -ExpectedValue $thumbnailProviderPath
    Assert-RegistryValue -Path $registrationPath -Name "InstallType" -ExpectedValue "Inno Setup"

    # Reinstalling the exact build must reuse the content-addressed provider
    # instead of attempting to replace files that Explorer may have loaded.
    Invoke-CheckedProcess -FilePath $resolvedInstaller -Arguments @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-",
        "/DIR=`"$resolvedInstallRoot`""
    )
    $thumbnailProvidersAfterReinstall = @(
        Get-ChildItem `
            -LiteralPath $thumbnailProviderRoot `
            -Filter "BundlePack.Thumbnail.comhost.dll" `
            -File `
            -Recurse
    )
    if ($thumbnailProvidersAfterReinstall.Count -ne 1 -or
        $thumbnailProvidersAfterReinstall[0].FullName -cne $thumbnailProviderPath) {
        throw "Reinstalling the same build created or selected a different thumbnail provider."
    }
}
finally {
    if ($installAttempted -and (Test-Path -LiteralPath $uninstallerPath -PathType Leaf)) {
        Invoke-CheckedProcess -FilePath $uninstallerPath -Arguments @(
            "/VERYSILENT",
            "/SUPPRESSMSGBOXES",
            "/NORESTART"
        )
    }
}

foreach ($removedPath in @(
    $progIdPath,
    $applicationPath,
    $capabilitiesPath,
    $registrationPath,
    $thumbnailClassPath,
    $thumbnailHandlerPath
)) {
    if (Test-Path -LiteralPath $removedPath) {
        throw "The installer did not remove its registry key: $removedPath"
    }
}
if (Test-Path -LiteralPath $bundlePackRegistryPath) {
    throw "The installer left an empty BundlePack registry key: $bundlePackRegistryPath"
}
Assert-RegistryValueAbsent -Path $openWithPath -Name "BundlePack.Archive.1"
Assert-RegistryValueAbsent -Path $registeredApplicationsPath -Name "BundlePack"
Assert-RegistryValueAbsent -Path $approvedExtensionsPath -Name $thumbnailClassId
if (Test-Path -LiteralPath $resolvedInstallRoot) {
    throw "The installer did not remove its application directory: $resolvedInstallRoot"
}

Write-Host "PASS: BundlePack installer registered, installed, unregistered, and removed the x64 application."
