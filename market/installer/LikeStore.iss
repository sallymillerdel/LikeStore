; Inno Setup script for the LikeStore Windows client (first install on a new PC).
; Built by market\build-installer.ps1, which passes:
;   /DAppVersion=<version from pubspec.yaml>  /DSourceDir=<flutter Release folder>
;   /DOutputDir=<where Setup goes>
;
; Per-user install, no admin/UAC. The user picks an apps folder ({app}, by
; default %LocalAppData%\LikeStore\apps) and the store goes into the same place
; its own self-update uses (windows_installer.dart):
;
;   {app}\com.likestore.market\<version>\
;
; The store recognises that layout, keeps its self-updates there and installs
; apps next to it ({app}\<app-id>\<version>\) unless Settings picks another
; folder. After the first self-update it removes this version folder like any
; other old version, so the uninstaller lives outside it, in
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
AppPublisher=SLSoft
AppComments=The official store for SLSoft apps
VersionInfoCompany=SLSoft
VersionInfoDescription=LikeStore - the official store for SLSoft apps
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DefaultDirName={#StoreRoot}\apps
; A newer Setup offers the folder of the existing install (see InitializeWizard).
UsePreviousAppDir=yes
DisableDirPage=no
AppendDefaultDirName=no
DirExistsWarning=no
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

#define StoreDir "{app}\" + MarketId + "\" + AppVersion

[Messages]
SelectDirDesc=Where should [name] and your apps be installed?
SelectDirLabel3=Setup will install [name] into this folder. Apps you install from [name] go here too; you can change that later in [name] Settings.

[Files]
Source: "{#SourceDir}\*"; DestDir: "{#StoreDir}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Same file the store itself maintains (Start Menu\Programs\LikeStore.lnk), so a
; self-update re-points it at the new version.
Name: "{userprograms}\{#AppName}"; Filename: "{#StoreDir}\{#AppExe}"; WorkingDir: "{#StoreDir}"

[Run]
Filename: "{#StoreDir}\{#AppExe}"; WorkingDir: "{#StoreDir}"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; "Start with Windows" (Settings) adds this value; it points into the folder being removed.
Filename: "{sys}\reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v {#AppName} /f"; Flags: runhidden; RunOnceId: "RemoveRunEntry"

[UninstallDelete]
; Every version of the store (installed by Setup or by self-update). Apps
; installed through the store ({app}\<other-id>\), their shortcuts and the
; store's settings are kept. The second line covers installs by Setup 1.0.0.
Type: filesandordirs; Name: "{app}\{#MarketId}"
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

procedure InitializeWizard();
var
  Dir: String;
begin
  // Setup 1.0.0 recorded the version folder ({app}\com.likestore.market\<version>)
  // as the install folder; offer the apps folder above it instead.
  Dir := RemoveBackslashUnlessRoot(WizardForm.DirEdit.Text);
  if CompareText(ExtractFileName(ExtractFileDir(Dir)), '{#MarketId}') = 0 then
    WizardForm.DirEdit.Text := ExtractFileDir(ExtractFileDir(Dir));
end;

function InitializeUninstall(): Boolean;
begin
  Result := WaitForStoreToClose();
end;
