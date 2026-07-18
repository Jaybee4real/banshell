#define AppVersion GetEnv("BANSHELL_VERSION")
#if AppVersion == ""
  #define AppVersion "1.11.1"
#endif

[Setup]
AppName=BANSHELL
AppVersion={#AppVersion}
AppPublisher=Jaybee
DefaultDirName={autopf}\BANSHELL
DefaultGroupName=BANSHELL
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Banshell.exe
OutputDir=.
OutputBaseFilename=Banshell-Setup
SetupIconFile=Banshell.ico
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern
CloseApplications=yes
RestartApplications=yes

[Files]
Source: "publish\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\BANSHELL"; Filename: "{app}\Banshell.exe"
Name: "{group}\Uninstall BANSHELL"; Filename: "{uninstallexe}"
Name: "{autostartup}\BANSHELL"; Filename: "{app}\Banshell.exe"; Tasks: startupicon

[Tasks]
Name: "startupicon"; Description: "Start BANSHELL automatically when Windows starts"; GroupDescription: "Startup:"

[Run]
Filename: "{app}\Banshell.exe"; Description: "Launch BANSHELL now"; Flags: nowait postinstall
