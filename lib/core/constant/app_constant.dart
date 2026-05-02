import 'package:copperlauncher_main/core/app_config.dart';
import 'package:path/path.dart' as p;

const appVersion = '0.0.1a';
final configPath = p.join('lib', 'config.json');

const githubMindustryUrl =
    'https://api.github.com/repos/Anuken/Mindustry/releases';

const githubBeUrl =
    'https://api.github.com/repos/Anuken/MindustryBuilds/releases';

const githubModMetaUrl =
    'https://raw.githubusercontent.com/Anuken/MindustryMods/master/mods.json';

const github3MonthsModMetaUrl =
    'https://raw.githubusercontent.com/Anuken/MindustryMods/@{3months}/mods.json';

String get githubToken => config.setting.githubToken;

Map<String,String> get modDownloadHeaders => {
  'User-Agent': 'MindustryModDownloader',
  'Authorization': 'token $githubToken',
};

Map<String,String> get gameDownloadHeaders => {
  'User-Agent': 'MindustryDownloader',
  'Authorization': 'token $githubToken',
};