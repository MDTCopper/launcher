import '../util/math/range.dart';

const appVersion = '0.0.1a';

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

///在146之前，不论是怎么类型的模组，都是一样的
///
///146-136=> 136
///
///135-105=> 105
///
///105-97 => 97 (这个版本往前就没有加载模组功能，可以说是远古版了)
///

final minModGameVersionModifier = RangeModifier(0, [
  RangeRuler(97, 104.9, 97),
  RangeRuler(105, 135.9, 105),
  RangeRuler(136, 158.9, 136),
  RangeRuler(158, double.infinity, 999),
]);

final minJavaModGameVersionModifier = RangeModifier(0, [
  RangeRuler(97, 105, 97),
  RangeRuler(105, 136, 105),
  RangeRuler(136, 147, 136),
  RangeRuler(147, 154, 147),
  RangeRuler(154, double.infinity, 154),
]);

// const minCopperModGameVersionMap = <String, double>{};
//147往后才能进行存档隔离
//142往后才支持控制窗口状态