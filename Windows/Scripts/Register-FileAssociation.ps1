[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ExecutablePath,
    [string]$ThumbnailProviderPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).ProviderPath
if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf) -or
    -not ([System.IO.Path]::GetExtension($resolvedExecutable).Equals(".exe", [StringComparison]::OrdinalIgnoreCase))) {
    throw "ExecutablePath must point to a Windows executable."
}

$resolvedThumbnailProvider = $null
if (-not [string]::IsNullOrWhiteSpace($ThumbnailProviderPath)) {
    $resolvedThumbnailProvider = (Resolve-Path -LiteralPath $ThumbnailProviderPath).ProviderPath
    if (-not (Test-Path -LiteralPath $resolvedThumbnailProvider -PathType Leaf) -or
        -not ([System.IO.Path]::GetFileName($resolvedThumbnailProvider).Equals(
            "BundlePack.Thumbnail.comhost.dll",
            [StringComparison]::OrdinalIgnoreCase))) {
        throw "ThumbnailProviderPath must point to BundlePack.Thumbnail.comhost.dll."
    }
}

$classesRoot = "HKCU:\Software\Classes"
$progId = "BundlePack.Archive.1"
$progIdPath = "$classesRoot\$progId"
$applicationName = [System.IO.Path]::GetFileName($resolvedExecutable)
$applicationPath = "$classesRoot\Applications\$applicationName"
$openCommand = "`"$resolvedExecutable`" `"%1`""
$registrationPath = "HKCU:\Software\BundlePack\Registration"
$registeredApplicationsPath = "HKCU:\Software\RegisteredApplications"

function Assert-CompatibleRegistryValue {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$Name,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$ExpectedValue
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $key = Get-Item -LiteralPath $Path
    try {
        if ($key.GetValueNames() -contains $Name) {
            $actual = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($actual -cne $ExpectedValue) {
                throw "Refusing to replace registry state that is not owned by this BundlePack build: $Path [$Name]"
            }
        }
    }
    finally {
        $key.Dispose()
    }
}

Assert-CompatibleRegistryValue -Path "$progIdPath\shell\open\command" -Name "" -ExpectedValue $openCommand
Assert-CompatibleRegistryValue -Path "$applicationPath\shell\open\command" -Name "" -ExpectedValue $openCommand
Assert-CompatibleRegistryValue `
    -Path $registeredApplicationsPath `
    -Name "BundlePack" `
    -ExpectedValue "Software\BundlePack\Capabilities"

$thumbnailClassId = "{645A25AB-1F31-4147-A47B-46E8515BF79D}"
$thumbnailHandlerId = "{E357FCCD-A995-4576-B01F-234630154E96}"
$thumbnailProviderValue = if ($null -eq $resolvedThumbnailProvider) { "" } else { $resolvedThumbnailProvider }
if ($null -ne $resolvedThumbnailProvider) {
    Assert-CompatibleRegistryValue `
        -Path "$classesRoot\CLSID\$thumbnailClassId\InprocServer32" `
        -Name "" `
        -ExpectedValue $resolvedThumbnailProvider
    Assert-CompatibleRegistryValue `
        -Path "$classesRoot\.bundlepack\shellex\$thumbnailHandlerId" `
        -Name "" `
        -ExpectedValue $thumbnailClassId
}

if (Test-Path -LiteralPath $registrationPath) {
    Assert-CompatibleRegistryValue -Path $registrationPath -Name "ExecutablePath" -ExpectedValue $resolvedExecutable
    Assert-CompatibleRegistryValue `
        -Path $registrationPath `
        -Name "ThumbnailProviderPath" `
        -ExpectedValue $thumbnailProviderValue
}

New-Item -Path $progIdPath -Force | Out-Null
Set-Item -Path $progIdPath -Value "BundlePack Archive"
New-ItemProperty -Path $progIdPath -Name "FriendlyTypeName" -PropertyType String -Value "BundlePack Archive" -Force | Out-Null

$defaultIconPath = "$progIdPath\DefaultIcon"
New-Item -Path $defaultIconPath -Force | Out-Null
Set-Item -Path $defaultIconPath -Value "`"$resolvedExecutable`",0"

$commandPath = "$progIdPath\shell\open\command"
New-Item -Path $commandPath -Force | Out-Null
Set-Item -Path $commandPath -Value $openCommand

$extensionOpenWithPath = "$classesRoot\.bundlepack\OpenWithProgids"
New-Item -Path $extensionOpenWithPath -Force | Out-Null
New-ItemProperty -Path $extensionOpenWithPath -Name $progId -PropertyType String -Value "" -Force | Out-Null

$applicationCommandPath = "$applicationPath\shell\open\command"
New-Item -Path $applicationPath -Force | Out-Null
New-ItemProperty -Path $applicationPath -Name "FriendlyAppName" -PropertyType String -Value "BundlePack" -Force | Out-Null
New-Item -Path $applicationCommandPath -Force | Out-Null
Set-Item -Path $applicationCommandPath -Value $openCommand
$supportedTypesPath = "$applicationPath\SupportedTypes"
New-Item -Path $supportedTypesPath -Force | Out-Null
New-ItemProperty -Path $supportedTypesPath -Name ".bundlepack" -PropertyType String -Value "" -Force | Out-Null

$capabilitiesPath = "HKCU:\Software\BundlePack\Capabilities"
New-Item -Path $capabilitiesPath -Force | Out-Null
New-ItemProperty -Path $capabilitiesPath -Name "ApplicationName" -PropertyType String -Value "BundlePack" -Force | Out-Null
New-ItemProperty -Path $capabilitiesPath -Name "ApplicationDescription" -PropertyType String -Value "Create and open BundlePack archives." -Force | Out-Null
$fileAssociationsPath = "$capabilitiesPath\FileAssociations"
New-Item -Path $fileAssociationsPath -Force | Out-Null
New-ItemProperty -Path $fileAssociationsPath -Name ".bundlepack" -PropertyType String -Value $progId -Force | Out-Null

New-Item -Path $registeredApplicationsPath -Force | Out-Null
New-ItemProperty -Path $registeredApplicationsPath -Name "BundlePack" -PropertyType String -Value "Software\BundlePack\Capabilities" -Force | Out-Null

if ($null -ne $resolvedThumbnailProvider) {
    $thumbnailClassPath = "$classesRoot\CLSID\$thumbnailClassId"
    New-Item -Path $thumbnailClassPath -Force | Out-Null
    Set-Item -Path $thumbnailClassPath -Value "BundlePack Thumbnail Provider"
    $thumbnailServerPath = "$thumbnailClassPath\InprocServer32"
    New-Item -Path $thumbnailServerPath -Force | Out-Null
    Set-Item -Path $thumbnailServerPath -Value $resolvedThumbnailProvider
    New-ItemProperty -Path $thumbnailServerPath -Name "ThreadingModel" -PropertyType String -Value "Both" -Force | Out-Null

    $thumbnailHandlerPath = "$classesRoot\.bundlepack\shellex\$thumbnailHandlerId"
    New-Item -Path $thumbnailHandlerPath -Force | Out-Null
    Set-Item -Path $thumbnailHandlerPath -Value $thumbnailClassId

    $approvedExtensionsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"
    New-Item -Path $approvedExtensionsPath -Force | Out-Null
    New-ItemProperty `
        -Path $approvedExtensionsPath `
        -Name $thumbnailClassId `
        -PropertyType String `
        -Value "BundlePack Thumbnail Provider" `
        -Force | Out-Null
}

New-Item -Path $registrationPath -Force | Out-Null
New-ItemProperty -Path $registrationPath -Name "ExecutablePath" -PropertyType String -Value $resolvedExecutable -Force | Out-Null
New-ItemProperty `
    -Path $registrationPath `
    -Name "ThumbnailProviderPath" `
    -PropertyType String `
    -Value $thumbnailProviderValue `
    -Force | Out-Null

if (-not ([System.Management.Automation.PSTypeName]"BundlePack.NativeShell").Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace BundlePack {
    public static class NativeShell {
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
    }
}
"@
}

[BundlePack.NativeShell]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Host "BundlePack was added to Open with for .bundlepack files."
if ($null -ne $resolvedThumbnailProvider) {
    Write-Host "The BundlePack Explorer thumbnail provider was registered."
}
Write-Host "Windows may still ask you to choose BundlePack as the default application."
