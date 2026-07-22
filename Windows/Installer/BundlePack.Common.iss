#ifndef SourceDir
  #error SourceDir must point to a prepared BundlePack Windows artifact.
#endif
#ifndef OutputDir
  #error OutputDir must point to the installer output directory.
#endif
#ifndef AppVersion
  #error AppVersion must contain the BundlePack application version.
#endif
#ifndef ThumbnailBundleId
  #error ThumbnailBundleId must identify the prepared thumbnail provider files.
#endif
#ifndef Architecture
  #error Architecture must be defined by the architecture-specific wrapper.
#endif
#ifndef AllowedArchitectures
  #error AllowedArchitectures must be defined by the architecture-specific wrapper.
#endif
#ifndef InstallArchitectures
  #error InstallArchitectures must be defined by the architecture-specific wrapper.
#endif

#define AppExecutable "BundlePack.Windows.exe"
#define ProgId "BundlePack.Archive.1"
#define ThumbnailClassId "{{645A25AB-1F31-4147-A47B-46E8515BF79D}"
#define ThumbnailHandlerId "{{E357FCCD-A995-4576-B01F-234630154E96}"

[Setup]
AppId=com.tuki0918.BundlePack
AppName=BundlePack
AppVersion={#AppVersion}
AppVerName=BundlePack {#AppVersion}
AppPublisher=tuki0918
AppPublisherURL=https://github.com/tuki0918/bundlepack
AppSupportURL=https://github.com/tuki0918/bundlepack/issues
AppUpdatesURL=https://github.com/tuki0918/bundlepack/releases
VersionInfoVersion={#AppVersion}
VersionInfoCompany=tuki0918
VersionInfoDescription=BundlePack installer ({#Architecture})
VersionInfoProductName=BundlePack
DefaultDirName={localappdata}\Programs\BundlePack
DefaultGroupName=BundlePack
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed={#AllowedArchitectures}
ArchitecturesInstallIn64BitMode={#InstallArchitectures}
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=BundlePack-Setup-{#Architecture}
SetupIconFile=..\BundlePack.Windows\Assets\AppIcon.ico
LicenseFile=..\..\LICENSE
UninstallDisplayIcon={app}\{#AppExecutable}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,Register-FileAssociation.ps1,Unregister-FileAssociation.ps1,README.txt,ThumbnailProvider\*"; Flags: ignoreversion recursesubdirs createallsubdirs
; Explorer can keep the previous COM host loaded after Restart Manager asks it to
; close. Each provider build therefore uses a content-addressed directory instead
; of replacing an in-use DLL. An exact reinstall skips the already installed set.
Source: "{#SourceDir}\ThumbnailProvider\*"; DestDir: "{app}\ThumbnailProvider\{#ThumbnailBundleId}"; Excludes: "*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: ShouldInstallThumbnailProvider

[Icons]
Name: "{group}\BundlePack"; Filename: "{app}\{#AppExecutable}"; WorkingDir: "{app}"

[Registry]
Root: HKCU; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueData: "BundlePack Archive"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueName: "FriendlyTypeName"; ValueData: "BundlePack Archive"
Root: HKCU; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueData: """{app}\{#AppExecutable}"",0"
Root: HKCU; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExecutable}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\.bundlepack"; ValueType: none; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Classes\.bundlepack\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue uninsdeletekeyifempty

Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExecutable}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "BundlePack"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExecutable}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExecutable}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExecutable}\SupportedTypes"; ValueType: string; ValueName: ".bundlepack"; ValueData: ""

Root: HKCU; Subkey: "Software\BundlePack"; ValueType: none; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\BundlePack\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "BundlePack"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\BundlePack\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Create and open BundlePack archives."
Root: HKCU; Subkey: "Software\BundlePack\Capabilities\FileAssociations"; ValueType: string; ValueName: ".bundlepack"; ValueData: "{#ProgId}"
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "BundlePack"; ValueData: "Software\BundlePack\Capabilities"; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\Classes\CLSID\{#ThumbnailClassId}"; ValueType: string; ValueData: "BundlePack Thumbnail Provider"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\CLSID\{#ThumbnailClassId}\InprocServer32"; ValueType: string; ValueData: "{app}\ThumbnailProvider\{#ThumbnailBundleId}\BundlePack.Thumbnail.comhost.dll"
Root: HKCU; Subkey: "Software\Classes\CLSID\{#ThumbnailClassId}\InprocServer32"; ValueType: string; ValueName: "ThreadingModel"; ValueData: "Both"
Root: HKCU; Subkey: "Software\Classes\.bundlepack\shellex"; ValueType: none; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Classes\.bundlepack\shellex\{#ThumbnailHandlerId}"; ValueType: string; ValueData: "{#ThumbnailClassId}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"; ValueType: string; ValueName: "{#ThumbnailClassId}"; ValueData: "BundlePack Thumbnail Provider"; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\BundlePack\Registration"; ValueType: string; ValueName: "ExecutablePath"; ValueData: "{app}\{#AppExecutable}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\BundlePack\Registration"; ValueType: string; ValueName: "ThumbnailProviderPath"; ValueData: "{app}\ThumbnailProvider\{#ThumbnailBundleId}\BundlePack.Thumbnail.comhost.dll"
Root: HKCU; Subkey: "Software\BundlePack\Registration"; ValueType: string; ValueName: "InstallType"; ValueData: "Inno Setup"

[Run]
Filename: "{app}\{#AppExecutable}"; Description: "Launch BundlePack"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[Code]
var
  ThumbnailProviderDecisionInitialized: Boolean;
  ThumbnailProviderNeedsInstall: Boolean;

function ShouldInstallThumbnailProvider(): Boolean;
begin
  if not ThumbnailProviderDecisionInitialized then
  begin
    ThumbnailProviderNeedsInstall := not FileExists(ExpandConstant(
      '{app}\ThumbnailProvider\{#ThumbnailBundleId}\.bundlepack-provider-id'));
    ThumbnailProviderDecisionInitialized := True;
  end;

  Result := ThumbnailProviderNeedsInstall;
end;
