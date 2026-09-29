; ═══════════════════════════════════════════════════════════════════════
; Inno Setup Script — ISKOLINIC Desktop App
; ═══════════════════════════════════════════════════════════════════════
;
; Usage:
;   iscc.exe /DMyAppVersion=1.0.0 installer.iss
;
; If MyAppVersion is not provided, defaults to "1.0.0".
; ═══════════════════════════════════════════════════════════════════════

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif

#define MyAppName "ISKOLINIC"
#define MyAppPublisher "Iskolinic Team"
#define MyAppExeName "iskolinic.exe"
#define MyAppId "{{A9F2D7E0-5B3C-4A1E-8D6F-2C9E7B4A3D1F}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppCopyright=Copyright (C) 2026 {#MyAppPublisher}. All rights reserved.
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
#ifndef MyOutputFilename
  #define MyOutputFilename "IskoLinic-Setup"
#endif
OutputDir=dist
OutputBaseFilename={#MyOutputFilename}
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
PrivilegesRequired=lowest
; Close the running app before installing (handles auto-updates too)
CloseApplications=force
CloseApplicationsFilter=iskolinic.exe
; Allow updating without uninstalling first
UsePreviousAppDir=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Include all files from the Flutter release build output
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "assets\installer_banner.bmp"; Flags: dontcopy



[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Launch the app after installation (including silent/auto-update mode)
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall

[Code]
// ═══════════════════════════════════════════════════════════════════
//  Uninstall: prompt user to delete AppData (patient database, etc.)
// ═══════════════════════════════════════════════════════════════════

// Force-kill the app process to release any locked files (e.g., clinic.db)
procedure KillAppProcess();
var
  ResultCode: Integer;
begin
  Exec('taskkill', '/F /IM {#MyAppExeName}', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // Small delay to let file handles fully release
  Sleep(1000);
end;

// Attempt to delete the app data directory. Falls back to shell command if needed.
procedure ForceDeleteDir(const DirPath: String; const ParentPath: String);
var
  ResultCode: Integer;
begin
  // First attempt: Inno Setup's built-in DelTree
  if DelTree(DirPath, True, True, True) then
  begin
    RemoveDir(ParentPath);
    Exit;
  end;

  // Fallback: use Windows shell command for stubborn files
  Exec('cmd.exe', '/C rmdir /S /Q "' + DirPath + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  RemoveDir(ParentPath);

  // If the directory still exists, notify the user
  if DirExists(DirPath) then
  begin
    MsgBox(
      'Some files could not be removed automatically.' + #13#10 +
      'You can manually delete this folder:' + #13#10 + #13#10 +
      DirPath,
      mbInformation,
      MB_OK
    );
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDataDir: String;
  ParentDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    AppDataDir := ExpandConstant('{userappdata}\Iskolinic Team\Iskolinic');
    ParentDir := ExpandConstant('{userappdata}\Iskolinic Team');

    if DirExists(AppDataDir) then
    begin
      if MsgBox(
        'Do you also want to remove all patient data and application settings?' + #13#10 + #13#10 +
        'This will permanently delete the clinic database and all saved data.' + #13#10 +
        'This action cannot be undone.',
        mbConfirmation,
        MB_YESNO or MB_DEFBUTTON2
      ) = IDYES then
      begin
        KillAppProcess();
        ForceDeleteDir(AppDataDir, ParentDir);
      end;
    end;
  end;
end;

procedure InitializeWizard();
var
  BannerImage: TBitmapImage;
begin
  // Extract and display custom banner on the Welcome page
  ExtractTemporaryFile('installer_banner.bmp');

  
  // Hide the default side image in modern style
  WizardForm.WizardBitmapImage.Visible := False;
  
  // Create and position the new top banner
  BannerImage := TBitmapImage.Create(WizardForm);
  BannerImage.Parent := WizardForm.WelcomePage;
  BannerImage.Bitmap.LoadFromFile(ExpandConstant('{tmp}\installer_banner.bmp'));

  BannerImage.Left := 0;
  BannerImage.Top := 0;
  BannerImage.Width := WizardForm.WelcomePage.Width;
  BannerImage.Height := BannerImage.Width div 4; // Maintain 16:4 (4:1) aspect ratio
  BannerImage.Stretch := True;

  // Move the welcome text below the banner
  WizardForm.WelcomeLabel1.Font.Size := 14;
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel1.Left := ScaleX(20);
  WizardForm.WelcomeLabel1.Top := BannerImage.Height + ScaleY(20);
  WizardForm.WelcomeLabel1.Width := WizardForm.WelcomePage.Width - ScaleX(40);
  
  WizardForm.WelcomeLabel2.Left := ScaleX(20);
  WizardForm.WelcomeLabel2.Top := WizardForm.WelcomeLabel1.Top + WizardForm.WelcomeLabel1.Height + ScaleY(10);
  WizardForm.WelcomeLabel2.Width := WizardForm.WelcomePage.Width - ScaleX(40);
end;

