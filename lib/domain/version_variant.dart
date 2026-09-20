import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/local_game_importer.dart';
import 'package:copper_launcher/domain/task.dart';
import 'package:copper_launcher/domain/tasks/loader_download_task.dart';
import 'package:copper_launcher/ui/components/button/action_button.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/input/outlined_text_field.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/validate/windows_file_name_validator.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// 变体可以从源版本继承的数据（数据目录下的条目）
enum VersionDataKind {
  mods('模组', 'mods'),
  copperMods('Copper 模组', 'copper/mods'),
  saves('存档', 'saves'),
  maps('地图', 'maps'),
  schematics('蓝图', 'schematics'),
  settings('游戏设置', 'settings.bin');

  const VersionDataKind(this.label, this.entryName);

  final String label;

  ///数据目录里的条目名：多数是单层目录，Copper 模组在 `copper/mods`
  final String entryName;

  ///在某个数据目录下对应的路径
  String pathIn(String dataPath) =>
      p.joinAll([dataPath, ...entryName.split('/')]);

  bool get isDirectory => this != VersionDataKind.settings;
}

/// 以 [source] 为模板新建一个变体版本
///
/// - 与源版本**共用游戏本体**（同一个 `jarPath`，删除时由 [VersionOptions.deleteVersion]
///   按引用计数决定要不要删文件），新 tag + 新目录
/// - 默认**开隔离**：不隔离的话新版本会继续用全局数据目录，跟源版本混在一起，"区分"就不成立
/// - [inherit] 里的数据从源版本的数据目录**拷贝**过去（拷贝而非链接：Windows 下目录符号
///   链接要开发者模式或管理员权限）
/// - [launcher] / [launcherPath] 用于「换一种启动方式建一个版本」：不传就与源版本一致
/// - [pendingLoader] 是「还在后台下载的 loader」：变体弹窗先开、用户在填名字与继承的
///   时候它在下；点「创建」后如果它还没结束，就先通知一声再等它，下完用真实路径建版本
///   （失败就不建版本）
///
/// 返回新建的版本；用户取消时返回 null
Future<Mindustry?> createVersionVariant({
  required Mindustry source,
  VersionFold? targetFold,
  BuildContext? context,
  LauncherType? launcher,
  String? launcherPath,
  LoaderDownloadTask? pendingLoader,
  String tagSuffix = '副本',
  String dialogTitle = '新建变体',
}) async {
  //不传 launcher 就是照抄源版本（含它用的 loader）；传了则以传入的为准
  final targetLauncher = launcher ?? source.launcher;
  var targetLauncherPath = launcher == null
      ? source.launcherPath
      : launcherPath;

  final options =
      await showAnimatedDialog<({String tag, Set<VersionDataKind> inherit})>(
        context: context,
        pageBuilder: (_, _, _) => _VariantDialog(
          source: source,
          usedTags: versionTags(),
          tagSuffix: tagSuffix,
          title: dialogTitle,
          launcher: targetLauncher,
        ),
      );
  if (options == null) return null;

  // 选的是远程 loader：弹窗期间它在后台下，这里等它（用户点创建时可能还没下完）
  if (pendingLoader != null) {
    if (pendingLoader.status == TaskStatus.process) {
      addNotice(
        icon: Icons.download,
        title: '等待加载器下载',
        content: 'Copper Loader ${pendingLoader.tag} 下完就建版本',
      );
    }
    try {
      targetLauncherPath = await pendingLoader.done;
    } catch (e) {
      addNotice(
        icon: Icons.close,
        title: '加载器没下下来',
        content: '没有创建版本：稍后再试，或改选本地 jar',
      );
      addLog(
        .warning,
        '变体创建中止：加载器没下下来（${removeNewlines('$e')}）',
        tag: 'Version',
      );
      return null;
    }
  }

  final fold = targetFold ?? _foldOf(source);
  final version = Mindustry(
    id: const Uuid().v4(),
    launcher: targetLauncher,
    launcherPath: targetLauncherPath,
    tag: options.tag,
    jarPath: source.jarPath,
    isBe: source.isBe,
    path: fold.path,
    release: source.release,
    addTime: DateTime.now(),
    isolation: true,
    versionNumber: source.versionNumber,
  );

  //先把数据拷好再入账：拷一半失败时不会留下一个"记录已有、数据不全"的版本
  final copied = <String>[];
  for (final kind in options.inherit) {
    final count = await _inheritFrom(source, version, kind);
    if (count > 0) copied.add('${kind.label}（$count 项）');
  }

  fold.versions.add(version);
  config.save();
  final launcherLabel = targetLauncher == LauncherType.copper ? 'Copper' : '原版';
  addLog(
    .info,
    '新建变体 [${version.tag}]：本体与 [${source.tag}] 共用，启动方式 $launcherLabel，'
    '数据目录 ${version.dataPath}，继承${copied.isEmpty ? '无' : copied.join('、')}',
    tag: 'Version',
  );
  addNotice(
    icon: Icons.check_box_outlined,
    title: '已新建变体',
    content: '[${version.tag}]（$launcherLabel）',
  );
  return version;
}

/// [version] 所在的 fold：变体默认跟源版本放一起；找不到就用默认文件夹
VersionFold _foldOf(Mindustry version) {
  for (final fold in config.versionOptions.versionFolds) {
    if (fold.versions.any((it) => it.id == version.id)) return fold;
  }
  return defaultVersionFold();
}

/// 把 [kind] 对应的数据从源版本拷到新版本，返回拷进来的条目数
///
/// 变体继承的实现入口，直接暴露出来给用例覆盖
@visibleForTesting
Future<int> inheritVersionData(
  Mindustry source,
  Mindustry target,
  VersionDataKind kind,
) => _inheritFrom(source, target, kind);

Future<int> _inheritFrom(
  Mindustry source,
  Mindustry target,
  VersionDataKind kind,
) async {
  final from = kind.pathIn(source.dataPath);
  final to = kind.pathIn(target.dataPath);

  if (kind.isDirectory) return _copyDirectory(from, to);

  final file = File(from);
  if (!await file.exists()) return 0;
  await Directory(target.dataPath).create(recursive: true);
  await file.copy(to);
  return 1;
}

/// 递归拷贝目录，返回拷贝的文件数（目标已存在的同名文件跳过，不覆盖）
Future<int> _copyDirectory(String from, String to) async {
  final source = Directory(from);
  if (!await source.exists()) return 0;

  var copied = 0;
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    final target = p.join(to, p.relative(entity.path, from: source.path));
    if (entity is Directory) {
      await Directory(target).create(recursive: true);
      continue;
    }
    if (entity is! File) continue;
    final dest = File(target);
    if (await dest.exists()) continue;
    await dest.parent.create(recursive: true);
    await entity.copy(target);
    copied++;
  }
  return copied;
}

/// 新建变体的参数弹窗：新 tag + 要继承哪几类数据
///
/// 给用例留的构造入口：弹窗类是私有的，测试里没法直接 new
@visibleForTesting
Widget buildVariantDialogForTest({
  required Mindustry source,
  required Set<String> usedTags,
  LauncherType launcher = LauncherType.mindustry,
  String tagSuffix = '副本',
}) => _VariantDialog(
  source: source,
  usedTags: usedTags,
  launcher: launcher,
  tagSuffix: tagSuffix,
);

/// 用例入口：完整走一遍参数弹窗并返回结果，但不落盘
@visibleForTesting
Future<({String tag, Set<VersionDataKind> inherit})?> showVariantDialogForTest({
  required BuildContext context,
  required Mindustry source,
  required Set<String> usedTags,
  LauncherType launcher = LauncherType.mindustry,
}) => showAnimatedDialog<({String tag, Set<VersionDataKind> inherit})>(
  context: context,
  pageBuilder: (_, _, _) =>
      _VariantDialog(source: source, usedTags: usedTags, launcher: launcher),
);

class _VariantDialog extends StatefulWidget {
  const _VariantDialog({
    required this.source,
    required this.usedTags,
    required this.launcher,
    this.tagSuffix = '副本',
    this.title = '新建变体',
  });

  final Mindustry source;

  ///已占用的版本 tag（跨 fold），用于查重
  final Set<String> usedTags;

  ///新版本用哪个启动器：决定「Copper 模组」这项继不继承（原版版本用不到它）
  final LauncherType launcher;

  ///默认新标签的后缀（换启动器新建时用「Copper」之类更好认）
  final String tagSuffix;

  final String title;

  @override
  State<_VariantDialog> createState() => _VariantDialogState();
}

class _VariantDialogState extends State<_VariantDialog> {
  late final TextEditingController _tagController = TextEditingController(
    text: '${widget.source.tag} ${widget.tagSuffix}',
  );

  late String? _error = _validate(_tagController.text);

  ///默认继承哪几类
  final Set<VersionDataKind> _inherit = {
    VersionDataKind.saves,
    VersionDataKind.maps,
    VersionDataKind.schematics,
    VersionDataKind.settings,
  };

  @override
  void initState() {
    super.initState();
    _sourceHasCopperMods = _hasCopperMods(widget.source);
    _tagController.addListener(
      () => setState(() => _error = _validate(_tagController.text)),
    );
  }

  ///源版本的数据目录里有没有 Copper 模组（只看顶层有没有东西，不用读完）
  static bool _hasCopperMods(Mindustry source) {
    final directory = Directory(
      VersionDataKind.copperMods.pathIn(source.dataPath),
    );
    if (!directory.existsSync()) return false;
    return directory.listSync().isNotEmpty;
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  ///校验标签：按去空格后的值判断（输入法常会带出首尾空格），
  ///创建时用的也是去空格后的值，两边保持一致
  String? _validate(String tag) {
    final trimmed = tag.trim();
    final error = WindowsFileNameValidator.tagValidate(trimmed);
    if (error != null) return error;
    if (widget.usedTags.contains(trimmed)) return '名称已存在';
    return null;
  }

  ///源版本有没有 Copper 模组（决定要不要给这个继承项）
  bool _sourceHasCopperMods = false;

  ///能继承的种类
  ///
  /// Copper 模组只在**从 Copper 版本建 Copper 版本**、且源版本确实有 Copper 模组时才列：
  /// 别的组合要么用不上它，要么搬过去也是空的
  List<VersionDataKind> get _kinds => [
    for (final kind in VersionDataKind.values)
      if (kind != VersionDataKind.copperMods ||
          (widget.launcher == LauncherType.copper &&
              widget.source.isViaLoader &&
              _sourceHasCopperMods))
        kind,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final screen = MediaQuery.of(context).size;

    return Center(
      child: Material(
        elevation: 8,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxWidth: screen.width * 0.5,
            maxHeight: screen.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              top: BorderSide(color: colors.border, width: 1.5),
              left: BorderSide(color: colors.border, width: 0.75),
              right: BorderSide(color: colors.border, width: 0.75),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              Text(
                '游戏本体与 [${widget.source.tag}] 共用，新版本默认开启存档隔离',
                style: theme.textTheme.bodySmall,
              ),
              OutlinedTextField(
                label: '新版本标签',
                controller: _tagController,
                error: _error,
              ),
              Text('要继承的数据', style: theme.textTheme.bodySmall),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final kind in _kinds)
                    ActionButton(
                      content: Text(kind.label),
                      selected: _inherit.contains(kind),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      onTap: () => setState(() {
                        _inherit.contains(kind)
                            ? _inherit.remove(kind)
                            : _inherit.add(kind);
                      }),
                    ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消',
                    onTap: () => Navigator.pop(context),
                  ),
                  IconTextButton(
                    icon: Icons.check,
                    content: '创建',
                    //名字不合法时不禁用：点了给一条明确的原因，
                    //否则按钮看着能点、点了没反应，用户不知道卡在哪
                    onTap: () {
                      final error = _validate(_tagController.text);
                      if (error != null) {
                        setState(() => _error = error);
                        addNotice(
                          icon: Icons.close,
                          title: '名字不可用',
                          content: error,
                        );
                        return;
                      }
                      Navigator.pop(context, (
                        tag: _tagController.text.trim(),
                        inherit: {..._inherit},
                      ));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
