import 'package:copperlauncher_main/core/app_config.dart';
import 'package:path/path.dart' as p;

const appVersion = '0.0.1a';
final configPath = p.join('lib', 'config.json');

///https://api.github.com
const githubAPI = 'https://api.github.com';

///https://github.com
const githubCOM = 'https://github.com';

///https://raw.githubusercontent.com
const githubRAW = 'https://raw.githubusercontent.com';

///$githubAPI/repos/Anuken/Mindustry/releases
const githubMindustryUrl = '$githubAPI/repos/Anuken/Mindustry/releases';

///$githubAPI/repos/Anuken/MindustryBuilds/releases
const githubBeUrl = '$githubAPI/repos/Anuken/MindustryBuilds/releases';

///$githubRAW/Anuken/MindustryMods/master/mods.json
const githubModMetaUrl = '$githubRAW/Anuken/MindustryMods/master/mods.json';

///$githubRAW/Anuken/MindustryMods/@{3months}/mods.json
const github3MonthsModMetaUrl =
    '$githubRAW/Anuken/MindustryMods/@{3months}/mods.json';

String get githubToken => config.setting.githubToken;

Map<String, String> get modDownloadHeaders =>
    {
  'User-Agent': 'MindustryModDownloader',
  'Authorization': 'token $githubToken',
};

Map<String, String> get gameDownloadHeaders =>
    {
  'User-Agent': 'MindustryDownloader',
  'Authorization': 'token $githubToken',
};
