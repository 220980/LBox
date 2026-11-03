; Inno Setup script for LBox (Flutter Windows release).
; Build the app first (dart run fl_build -p windows), then compile this with:
;   "C:\Users\Administrator\AppData\Local\Programs\Inno Setup 6\ISCC.exe" LBox.iss

#define AppName "LBox"
#define AppVersion "1.0.1856"
#define AppPublisher "LBox"
#define AppExeName "LBox.exe"
#define SrcDir "D:\DIYSSH\flutter_server_box-main\build\windows\x64\runner\Release"

[Setup]
; A stable AppId keeps upgrades and uninstall entries attached to one app.
AppId={{3F2A6C1D-9B47-4E2A-8C15-7D6E1B9A3F52}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=D:\DIYSSH\flutter_server_box-main
OutputBaseFilename=LBox_Setup_{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installing under Program Files and writing the shared desktop need admin.
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
VersionInfoVersion=1.0.1856.0
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional tasks:"; Flags: checkedonce

[Files]
; The whole Flutter release folder: the exe, its DLLs and data\app.so.
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; The VC++ 2015-2022 x64 runtime, so a target PC without it still runs. Windows
; keeps its own copy when present; these sit beside the exe like any other DLL.
Source: "D:\DIYSSH\tools\VSBuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
