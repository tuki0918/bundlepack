[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath,
    [Parameter(Mandatory = $true)]
    [string]$ThumbnailProviderPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).ProviderPath
$resolvedThumbnailProvider = (Resolve-Path -LiteralPath $ThumbnailProviderPath).ProviderPath
$executableName = [System.IO.Path]::GetFileName($resolvedExecutable)
$windowsRoot = Split-Path -Parent $PSScriptRoot
$registerScript = Join-Path $windowsRoot "Scripts\Register-FileAssociation.ps1"
$unregisterScript = Join-Path $windowsRoot "Scripts\Unregister-FileAssociation.ps1"

$classesRoot = "HKCU:\Software\Classes"
$progId = "BundlePack.Archive.1"
$progIdPath = "$classesRoot\$progId"
$applicationPath = "$classesRoot\Applications\$executableName"
$openWithPath = "$classesRoot\.bundlepack\OpenWithProgids"
$bundlePackRegistryPath = "HKCU:\Software\BundlePack"
$capabilitiesPath = "HKCU:\Software\BundlePack\Capabilities"
$registeredApplicationsPath = "HKCU:\Software\RegisteredApplications"
$thumbnailClassId = "{645A25AB-1F31-4147-A47B-46E8515BF79D}"
$thumbnailHandlerId = "{E357FCCD-A995-4576-B01F-234630154E96}"
$thumbnailClassPath = "$classesRoot\CLSID\$thumbnailClassId"
$thumbnailHandlerPath = "$classesRoot\.bundlepack\shellex\$thumbnailHandlerId"
$approvedExtensionsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"
$registrationPath = "HKCU:\Software\BundlePack\Registration"

function Get-RequiredRegistryValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "The expected registry key does not exist: $Path"
    }

    $key = Get-Item -LiteralPath $Path
    try {
        if ($key.GetValueNames() -notcontains $Name) {
            throw "The expected registry value does not exist: $Path [$Name]"
        }

        return $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    }
    finally {
        $key.Dispose()
    }
}

function Assert-RegistryValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ExpectedValue
    )

    $actualValue = Get-RequiredRegistryValue -Path $Path -Name $Name
    if ($actualValue -cne $ExpectedValue) {
        throw "Unexpected registry value at $Path [$Name]. Expected '$ExpectedValue', found '$actualValue'."
    }
}

function Assert-RegistryValueAbsent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
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

if ((Test-Path -LiteralPath $progIdPath) -or
    (Test-Path -LiteralPath $applicationPath) -or
    (Test-Path -LiteralPath $capabilitiesPath) -or
    (Test-Path -LiteralPath $registrationPath) -or
    (Test-Path -LiteralPath $thumbnailClassPath) -or
    (Test-Path -LiteralPath $thumbnailHandlerPath)) {
    throw "The file-association test requires a clean per-user BundlePack registration."
}
Assert-RegistryValueAbsent -Path $registeredApplicationsPath -Name "BundlePack"
Assert-RegistryValueAbsent -Path $approvedExtensionsPath -Name $thumbnailClassId

try {
    & $registerScript `
        -ExecutablePath $resolvedExecutable `
        -ThumbnailProviderPath $resolvedThumbnailProvider

    $openCommand = "`"$resolvedExecutable`" `"%1`""
    Assert-RegistryValue -Path $progIdPath -Name "" -ExpectedValue "BundlePack Archive"
    Assert-RegistryValue -Path $progIdPath -Name "FriendlyTypeName" -ExpectedValue "BundlePack Archive"
    Assert-RegistryValue -Path "$progIdPath\DefaultIcon" -Name "" -ExpectedValue "`"$resolvedExecutable`",0"
    Assert-RegistryValue -Path "$progIdPath\shell\open\command" -Name "" -ExpectedValue $openCommand
    Assert-RegistryValue -Path $openWithPath -Name $progId -ExpectedValue ""
    Assert-RegistryValue -Path $applicationPath -Name "FriendlyAppName" -ExpectedValue "BundlePack"
    Assert-RegistryValue -Path "$applicationPath\shell\open\command" -Name "" -ExpectedValue $openCommand
    Assert-RegistryValue -Path "$applicationPath\SupportedTypes" -Name ".bundlepack" -ExpectedValue ""
    Assert-RegistryValue -Path $capabilitiesPath -Name "ApplicationName" -ExpectedValue "BundlePack"
    Assert-RegistryValue -Path $capabilitiesPath -Name "ApplicationDescription" -ExpectedValue "Create and open BundlePack archives."
    Assert-RegistryValue -Path "$capabilitiesPath\FileAssociations" -Name ".bundlepack" -ExpectedValue $progId
    Assert-RegistryValue -Path $registeredApplicationsPath -Name "BundlePack" -ExpectedValue "Software\BundlePack\Capabilities"
    Assert-RegistryValue -Path $thumbnailClassPath -Name "" -ExpectedValue "BundlePack Thumbnail Provider"
    Assert-RegistryValue -Path "$thumbnailClassPath\InprocServer32" -Name "" -ExpectedValue $resolvedThumbnailProvider
    Assert-RegistryValue -Path "$thumbnailClassPath\InprocServer32" -Name "ThreadingModel" -ExpectedValue "Both"
    Assert-RegistryValue -Path $thumbnailHandlerPath -Name "" -ExpectedValue $thumbnailClassId
    Assert-RegistryValue -Path $approvedExtensionsPath -Name $thumbnailClassId -ExpectedValue "BundlePack Thumbnail Provider"
    Assert-RegistryValue -Path $registrationPath -Name "ExecutablePath" -ExpectedValue $resolvedExecutable
    Assert-RegistryValue -Path $registrationPath -Name "ThumbnailProviderPath" -ExpectedValue $resolvedThumbnailProvider
}
finally {
    & $unregisterScript -ExecutableName $executableName
}

if (Test-Path -LiteralPath $progIdPath) {
    throw "The ProgID was not removed."
}
if (Test-Path -LiteralPath $applicationPath) {
    throw "The application registration was not removed."
}
if (Test-Path -LiteralPath $capabilitiesPath) {
    throw "The application capabilities were not removed."
}
if (Test-Path -LiteralPath $thumbnailClassPath) {
    throw "The thumbnail COM class was not removed."
}
if (Test-Path -LiteralPath $thumbnailHandlerPath) {
    throw "The thumbnail handler association was not removed."
}
if (Test-Path -LiteralPath $registrationPath) {
    throw "The registration ownership marker was not removed."
}
if (Test-Path -LiteralPath $bundlePackRegistryPath) {
    throw "The empty BundlePack registry key was not removed."
}
Assert-RegistryValueAbsent -Path $openWithPath -Name $progId
Assert-RegistryValueAbsent -Path $registeredApplicationsPath -Name "BundlePack"
Assert-RegistryValueAbsent -Path $approvedExtensionsPath -Name $thumbnailClassId

Write-Host "PASS: Windows file and thumbnail association registration and cleanup"
