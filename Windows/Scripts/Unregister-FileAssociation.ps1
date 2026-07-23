[CmdletBinding()]
param(
    [string]$ExecutableName = "BundlePack.Windows.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([System.IO.Path]::GetFileName($ExecutableName) -ne $ExecutableName -or
    -not ([System.IO.Path]::GetExtension($ExecutableName).Equals(".exe", [StringComparison]::OrdinalIgnoreCase))) {
    throw "ExecutableName must be an executable file name without a directory path."
}

$classesRoot = "HKCU:\Software\Classes"
$progId = "BundlePack.Archive.1"
$progIdPath = "$classesRoot\$progId"
$applicationPath = "$classesRoot\Applications\$ExecutableName"
$extensionOpenWithPath = "$classesRoot\.bundlepack\OpenWithProgids"
$bundlePackRegistryPath = "HKCU:\Software\BundlePack"
$capabilitiesPath = "HKCU:\Software\BundlePack\Capabilities"
$registeredApplicationsPath = "HKCU:\Software\RegisteredApplications"
$thumbnailClassId = "{645A25AB-1F31-4147-A47B-46E8515BF79D}"
$thumbnailHandlerId = "{E357FCCD-A995-4576-B01F-234630154E96}"
$thumbnailClassPath = "$classesRoot\CLSID\$thumbnailClassId"
$thumbnailHandlerPath = "$classesRoot\.bundlepack\shellex\$thumbnailHandlerId"
$approvedExtensionsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"
$registrationPath = "HKCU:\Software\BundlePack\Registration"

if (-not (Test-Path -LiteralPath $registrationPath)) {
    throw "No BundlePack-owned file-association registration was found. Nothing was removed."
}

$registrationKey = Get-Item -LiteralPath $registrationPath
try {
    $ownedExecutable = [string]$registrationKey.GetValue("ExecutablePath", "")
    $ownedThumbnailProvider = [string]$registrationKey.GetValue("ThumbnailProviderPath", "")
}
finally {
    $registrationKey.Dispose()
}
if ([System.IO.Path]::GetFileName($ownedExecutable) -cne $ExecutableName) {
    throw "The existing registration belongs to a different BundlePack executable. Nothing was removed."
}
$ownedOpenCommand = "`"$ownedExecutable`" `"%1`""

function Assert-OwnedRegistryValue {
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
                throw "Registry ownership changed; refusing to remove: $Path [$Name]"
            }
        }
    }
    finally {
        $key.Dispose()
    }
}

Assert-OwnedRegistryValue -Path "$progIdPath\shell\open\command" -Name "" -ExpectedValue $ownedOpenCommand
Assert-OwnedRegistryValue -Path "$applicationPath\shell\open\command" -Name "" -ExpectedValue $ownedOpenCommand
Assert-OwnedRegistryValue `
    -Path $registeredApplicationsPath `
    -Name "BundlePack" `
    -ExpectedValue "Software\BundlePack\Capabilities"
if (-not [string]::IsNullOrWhiteSpace($ownedThumbnailProvider)) {
    Assert-OwnedRegistryValue `
        -Path "$thumbnailClassPath\InprocServer32" `
        -Name "" `
        -ExpectedValue $ownedThumbnailProvider
    Assert-OwnedRegistryValue -Path $thumbnailHandlerPath -Name "" -ExpectedValue $thumbnailClassId
}

if (Test-Path -LiteralPath $progIdPath) {
    Remove-Item -LiteralPath $progIdPath -Recurse -Force
}
if (Test-Path -LiteralPath $applicationPath) {
    Remove-Item -LiteralPath $applicationPath -Recurse -Force
}
if (Test-Path -LiteralPath $extensionOpenWithPath) {
    Remove-ItemProperty -LiteralPath $extensionOpenWithPath -Name $progId -ErrorAction SilentlyContinue
}
if (Test-Path -LiteralPath $capabilitiesPath) {
    Remove-Item -LiteralPath $capabilitiesPath -Recurse -Force
}
if (Test-Path -LiteralPath $registeredApplicationsPath) {
    Remove-ItemProperty -LiteralPath $registeredApplicationsPath -Name "BundlePack" -ErrorAction SilentlyContinue
}
if (-not [string]::IsNullOrWhiteSpace($ownedThumbnailProvider)) {
    if (Test-Path -LiteralPath $thumbnailHandlerPath) {
        Remove-Item -LiteralPath $thumbnailHandlerPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $thumbnailClassPath) {
        Remove-Item -LiteralPath $thumbnailClassPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $approvedExtensionsPath) {
        Remove-ItemProperty `
            -LiteralPath $approvedExtensionsPath `
            -Name $thumbnailClassId `
            -ErrorAction SilentlyContinue
    }
}
Remove-Item -LiteralPath $registrationPath -Recurse -Force

if (Test-Path -LiteralPath $bundlePackRegistryPath) {
    $bundlePackRegistryKey = Get-Item -LiteralPath $bundlePackRegistryPath
    try {
        $bundlePackRegistryIsEmpty = (
            $bundlePackRegistryKey.SubKeyCount -eq 0 -and
            $bundlePackRegistryKey.ValueCount -eq 0
        )
    }
    finally {
        $bundlePackRegistryKey.Dispose()
    }
    if ($bundlePackRegistryIsEmpty) {
        Remove-Item -LiteralPath $bundlePackRegistryPath -Force
    }
}

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
Write-Host "BundlePack was removed from Open with for .bundlepack files."
