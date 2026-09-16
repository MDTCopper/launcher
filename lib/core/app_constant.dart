// ===== 版本信息（由 tool/build_release.dart 生成，勿手改）=====
///UI 显示的版本号，形如 v0.0.2 / v0.0.2 alpha 12 / v0.0.2 beta 7
const appVersion = 'v0.0.1 alpha 2';

///本次构建的 build number，同一版本重复构建时可选择不计入
const appBuildNumber = 2;

///本次构建时间
const appBuildTime = '2026-09-16 19:54';
// ===== 版本信息结束 =====

///https://api.github.com
const githubAPI = 'https://api.github.com';

///https://github.com
const githubCOM = 'https://github.com';

///https://raw.githubusercontent.com
const githubRAW = 'https://raw.githubusercontent.com';

///remote 数据源（copper launcher 自身仓库）raw 根地址
const remoteRawBase = '$githubRAW/MDTCopper/launcher/main/remote/';

///启动器本体仓库地址
const launcherRepoUrl = '$githubCOM/MDTCopper/launcher';

///版本设置适配索引文件名（引导拉取各版本 json）
const settingAdapterIndexFile = 'setting_adapter_index.hjson';

///github 镜像预设节点文件名（remote/ 根目录）
const githubMirrorsFile = 'github_mirrors.hjson';

///模组版本门禁文件名（remote/ 根目录，游戏版本区间 → 模组最低版本）
const mmgvmFile = 'mmgvm.hjson';

///官方版本列表快照文件名（remote/ 根目录）
///
///历史版本不变，存快照里；启动只用 API 补最新一页
const mindustryVersionsFile = 'mindustry_versions.json';

///版本列表每次向 API 取多少条（GitHub 列表接口一页上限就是 100）
const mindustryVersionPageSize = 100;

///$githubAPI/repos/Anuken/Mindustry/releases
const githubMindustryUrl = '$githubAPI/repos/Anuken/Mindustry/releases';

///$githubAPI/repos/Anuken/MindustryBuilds/releases
const githubBeUrl = '$githubAPI/repos/Anuken/MindustryBuilds/releases';

///$githubRAW/Anuken/MindustryMods/master/mods.json
const githubModMetaUrl = '$githubRAW/Anuken/MindustryMods/master/mods.json';

///$githubRAW/Anuken/MindustryMods/@{3months}/mods.json
const github3MonthsModMetaUrl =
    '$githubRAW/Anuken/MindustryMods/@{3months}/mods.json';

/// mindustry.top 资源站地图接口基址（站点拥有者公开的接口，前端可直连）；
/// 站点页面 www.mindustry.top/map 经 Nuxt 服务端把 /api 前缀代理到此处
const mindustryTopApiBase = 'https://api.mindustry.top';

// 模组版本门禁（各游戏版本 → 模组最低版本）已外置到 remote/mmgvm.hjson，
// 由 lib/data/min_game_versions.dart 加载，此处不再硬编码

const kDefaultAnimationDuration = Duration(milliseconds: 300);

const kDefaultFastAnimationSwitcherDuration = Duration(milliseconds: 200);

const kDefaultAnimationSwitcherDuration = Duration(milliseconds: 200);
