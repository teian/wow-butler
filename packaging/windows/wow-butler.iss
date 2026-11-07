; Inno Setup script for the WoW Butler setup .exe.
;
; Built by tool/build_desktop.dart, which passes:
;   /DAppVersion=1.2.3[-pre]  /DFileVersion=1.2.3  /DArch=x64|arm64  /DSourceDir=<Release folder>
;   /DOutputDir=<dist>  /DOutputName=<file name without .exe>

#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef OutputName
  #error OutputName is required
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#if Arch == "x64"
  #define InnoArch "x64compatible"
#else
  #define InnoArch Arch
#endif

[Setup]
; Stable identity: keep this AppId so upgrades replace the existing install.
AppId={{24F234BA-EDDC-4FD9-9D35-739219E486E4}
AppName=WoW Butler
AppVersion={#AppVersion}
AppVerName=WoW Butler {#AppVersion}
AppPublisher=Frank Gehann
AppPublisherURL=https://github.com/teian/wow-butler
AppSupportURL=https://github.com/teian/wow-butler/issues
VersionInfoVersion={#FileVersion}
DefaultDirName={autopf}\WoW Butler
DisableProgramGroupPage=yes
; Per-user install by default; the dialog offers an all-users install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed={#InnoArch}
ArchitecturesInstallIn64BitMode={#InnoArch}
LicenseFile={#SourcePath}..\..\LICENSE
SetupIconFile={#SourcePath}..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\wow_butler.exe
UninstallDisplayName=WoW Butler
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Flutter assets change between versions; drop the old ones on upgrade.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\WoW Butler"; Filename: "{app}\wow_butler.exe"
Name: "{autodesktop}\WoW Butler"; Filename: "{app}\wow_butler.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\wow_butler.exe"; Description: "{cm:LaunchProgram,WoW Butler}"; Flags: nowait postinstall skipifsilent
