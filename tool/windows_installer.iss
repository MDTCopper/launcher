; Copper Launcher Windows 安装包脚本（Inno Setup 6）
;
; 由 tool/build_release.dart 用 ISCC 编译，版本 / 目录 / 图标都从命令行 /D 注入，
; 平时不需要改这份模板：
;   ISCC.exe /DAppVersion=... /DSourceDir=... /DOutputDir=... /DOutputBaseName=... /DSetupIconFile=... windows_installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\dist"
#endif
#ifndef OutputBaseName
  #define OutputBaseName "copper-launcher-setup"
#endif
; 简体中文语言文件（Inno 官方安装包不带中文，这份取自 issrc 仓库，
; 由 kira-96/Inno-Setup-Chinese-Simplified-Translation 维护，文件头保留了作者信息）
; build_release.dart 会注入绝对路径；直接手动编译时走这个相对路径
#ifndef ChineseMessagesFile
  #define ChineseMessagesFile "languages\ChineseSimplified.isl"
#endif

[Setup]
; AppId 固定不变，升级安装才会识别成同一个应用（换了它就会变成两个程序）
AppId={{8F2A6C41-7B3E-4E7A-9C1D-5A0B7E4F2C93}
AppName=Copper Launcher
AppVersion={#AppVersion}
AppVerName=Copper Launcher {#AppVersion}
; 默认「仅为我安装」：不触发 UAC，双击就能装
;   {autopf} 会跟着降级成 %LOCALAPPDATA%\Programs，图标/开始菜单也走用户目录
; 向导里仍能改选「为所有用户安装」（那时才会弹 UAC，装到 Program Files）
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
DefaultDirName={autopf}\Copper Launcher
DefaultGroupName=Copper Launcher
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 未做代码签名：安装包会触发 SmartScreen 提示（详见项目进度文档）
#ifdef SetupIconFile
SetupIconFile={#SetupIconFile}
#endif
UninstallDisplayIcon={app}\copper_launcher.exe

[Languages]
; 中文系统自动选简体中文（ShowLanguageDialog 默认 auto）；其它语言走英文
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "{#ChineseMessagesFile}"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
; 整个 Release 目录（exe + dll + data）都装进去
; Excludes：不带构建目录里的启动器运行时数据（config 等本机调试残留，
; 打进包会让安装后的启动器把数据目录落到安装目录，版本路径指向构建机）
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "config.json,config.bin,control.lock,single_instance.port,logs,remote_data,versions,versionsFolds,mindustrys,java"

[Icons]
Name: "{group}\Copper Launcher"; Filename: "{app}\copper_launcher.exe"
Name: "{autodesktop}\Copper Launcher"; Filename: "{app}\copper_launcher.exe"; Tasks: desktopicon

[Run]
; 覆盖式更新的迁移钩子：新版带来的引导脚本先跑（没有这个文件就跳过），
; 参数是「目标版本 [来源版本]」（都是 release tag 形态；没有来源版本时只给一个参数），
; 跑完再让用户启动启动器
Filename: "{app}\update.cmd"; Parameters: "v{#AppVersion}{code:GetPreviousVersion}"; Flags: runhidden waituntilterminated skipifdoesntexist
Filename: "{app}\copper_launcher.exe"; Description: "立即运行 Copper Launcher"; Flags: nowait postinstall skipifsilent

[Code]
var
  PreviousVersion: String;

// 安装开始前把旧版本的 DisplayVersion 记下来：等 [Run] 执行的时候，
// 注册表里这个值已经被新版覆盖了
procedure ReadPreviousVersion();
var
  UninstallKey: String;
begin
  // 键名 = Uninstall\<AppId>_is1；AppId 见上面的 [Setup] 段（固定不变，所以这里可以写死）
  UninstallKey := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F2A6C41-7B3E-4E7A-9C1D-5A0B7E4F2C93}_is1';
  if not RegQueryStringValue(HKCU, UninstallKey, 'DisplayVersion', PreviousVersion) then
    RegQueryStringValue(HKLM, UninstallKey, 'DisplayVersion', PreviousVersion);
end;

function InitializeSetup(): Boolean;
begin
  ReadPreviousVersion();
  Result := True;
end;

// 来源版本参数：注册表里存的是 0.0.1-alpha5 这种，补上 v 前缀并带上引号；
// 没有旧版本时返回空串 —— 整个参数都不给，免得脚本收到一个字面量的 ""
function GetPreviousVersion(Param: String): String;
begin
  if PreviousVersion = '' then
    Result := ''
  else
    Result := ' "v' + PreviousVersion + '"';
end;
