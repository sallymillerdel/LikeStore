; Inno Setup script for the LikeStore Windows client (first install on a new PC).
; Built by market\build-installer.ps1, which passes:
;   /DAppVersion=<version from pubspec.yaml>  /DSourceDir=<flutter Release folder>
;   /DOutputDir=<where Setup goes>
;
; Per-user install, no admin/UAC. The files go into the same place the store's
; own self-update uses (windows_installer.dart):
;
;   %LocalAppData%\LikeStore\apps\com.likestore.market\<version>\
;
; so after the first self-update the store simply removes this folder like any
; other old version. The uninstaller therefore lives outside it, in
; %LocalAppData%\LikeStore\uninstall\.

#ifndef AppVersion
  #error AppVersion is not defined. Build with market\build-installer.ps1.
#endif
#ifndef SourceDir
  #error SourceDir is not defined. Build with market\build-installer.ps1.
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

#define AppName   "LikeStore"
#define AppExe    "LikeStore.exe"
#define MarketId  "com.likestore.market"
#define StoreRoot "{localappdata}\LikeStore"

[Setup]
; Keep this AppId forever: it is how a newer Setup finds the existing install.
AppId={{469D48EE-4129-45E0-A061-8CB57497F8FA}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultDirName={#StoreRoot}\apps\{#MarketId}\{#AppVersion}
UsePreviousAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
UninstallFilesDir={#StoreRoot}\uninstall
UninstallDisplayName={#AppName}
UninstallDisplayIcon={uninstallexe}
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=LikeStore-Setup-{#AppVersion}

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Same file the store itself maintains (Start Menu\Programs\LikeStore.lnk), so a
; self-update re-points it at the new version.
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Every version of the store (installed by Setup or by self-update). Apps
; installed through the store (apps\<other-id>\), their shortcuts and the
; store's settings are kept.
Type: filesandordirs; Name: "{#StoreRoot}\apps\{#MarketId}"
Type: files; Name: "{userdesktop}\{#AppName}.lnk"

[Code]
function StoreIsRunning(): Boolean;
var
  Code: Integer;
begin
  // find exits with 0 when tasklist printed a LikeStore.exe line.
  Result := Exec(ExpandConstant('{cmd}'),
    '/C tasklist /NH /FI "IMAGENAME eq {#AppExe}" | find /I "{#AppExe}"',
    '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
end;

function WaitForStoreToClose(): Boolean;
begin
  Result := True;
  while StoreIsRunning() do
    if SuppressibleMsgBox('{#AppName} is running. Close it, then click Retry.',
         mbError, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
end;

function InitializeSetup(): Boolean;
begin
  Result := WaitForStoreToClose();
end;

function InitializeUninstall(): Boolean;
begin
  Result := WaitForStoreToClose();
end;
