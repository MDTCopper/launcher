import 'dart:io';

import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/domain/loader_library.dart';
import 'package:copper_launcher/domain/loader_support.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/overlay_layer/dropdown_layer.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/ui/util/notification.dart';
import 'package:copper_launcher/util/io/path_selector.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 选加载器的结果
///
/// [loaderPath] 为 null 表示选了「不用加载器（原版启动）」；
/// 整个返回值为 null 表示用户取消（保持原状）
typedef LoaderPickResult = ({String? loaderPath});

/// 本地 jar 的类型过滤：选择页与下载页挑文件都用它
const loaderJarTypeGroup = XTypeGroup(label: 'Copper 加载器', extensions: ['jar']);

/// 弹选择页，**只返回选了什么**（库里已有的 / 远程待下载 / 去挑本地 jar / 不用加载器）
///
/// 取消返回 null。要的是「下载与落地由调用方决定」时用它（比如下载游戏：把 loader 的
/// 下载并进本体下载任务）；只想要最终路径就用 [showLoaderPicker]
Future<LoaderChoice?> pickLoaderChoice(
  BuildContext context, {
  String? currentLoaderPath,
  String? gameVersion,
  bool allowNone = false,
}) => showAnimatedDialog<LoaderChoice>(
  context: context,
  pageBuilder: (_, _, _) => _LoaderPickerDialog(
    currentLoaderPath: currentLoaderPath,
    gameVersion: gameVersion,
    allowNone: allowNone,
  ),
);

/// 弹加载器选择页：库内已有的（直接复用）／远程可下的（下载）／本地 jar
///
/// 拿到选择后在这里就落地（库内的直接用、本地的收进库、远程的先下载），
/// 返回的是**可直接用的 loader 绝对路径**；取消返回 null
///
/// [gameVersion] 传游戏版本的可比形式（[Mindustry.gameVersionString]）时会按适配表
/// 标注兼容性与推荐；拿不到就只列版本不做标注（比如下载游戏前还不知道大版本号）
Future<LoaderPickResult?> showLoaderPicker(
  BuildContext context, {
  String? currentLoaderPath,
  String? gameVersion,
  bool allowNone = false,
}) async {
  final choice = await pickLoaderChoice(
    context,
    currentLoaderPath: currentLoaderPath,
    gameVersion: gameVersion,
    allowNone: allowNone,
  );
  if (choice == null) return null;

  if (choice.useNone) return (loaderPath: null);

  if (!context.mounted) return null;
  final loaderPath = await _resolveChoice(context, choice);
  if (loaderPath == null) return null;
  return (loaderPath: loaderPath);
}

/// 把选择结果落成一个可用的 loader 路径：库内的直接用，本地的收进库，远程的先下
Future<String?> _resolveChoice(
  BuildContext context,
  LoaderChoice choice,
) async {
  if (choice.loaderPath case final path?) return path;

  if (choice.pickLocalFile) {
    final picked = await PathSelector.selectFile(
      acceptedTypeGroups: const [loaderJarTypeGroup],
    );
    if (picked == null || !context.mounted) return null;
    try {
      return await LoaderLibrary.importIntoLibrary(File(picked));
    } catch (e) {
      addNotice(icon: Icons.close, title: '添加失败', content: '无法把加载器复制进加载器库');
      debugPrint('添加加载器失败：$e');
      return null;
    }
  }

  final remote = choice.remote;
  if (remote == null) return null;
  addNotice(
    icon: Icons.download,
    title: '正在下载加载器',
    content: 'Copper Loader ${remote.tag}',
  );
  try {
    return await LoaderLibrary.downloadDesktop(
      tag: remote.tag,
      url: remote.url,
    );
  } catch (e) {
    addNotice(
      icon: Icons.close,
      title: '下载失败',
      content: '加载器没下下来：稍后再试或选本地 jar',
    );
    debugPrint('下载加载器失败：$e');
    return null;
  }
}

class _LoaderPickerDialog extends StatefulWidget {
  const _LoaderPickerDialog({
    this.currentLoaderPath,
    this.gameVersion,
    this.allowNone = false,
  });

  ///当前版本在用的 loader（在列表里标出来）
  final String? currentLoaderPath;

  ///当前游戏版本的可比形式（见 [Mindustry.gameVersionString]），用来判断兼不兼容
  final String? gameVersion;

  ///是否给「不用加载器（原版启动）」这一项
  final bool allowNone;

  @override
  State<_LoaderPickerDialog> createState() => _LoaderPickerDialogState();
}

class _LoaderPickerDialogState extends State<_LoaderPickerDialog> {
  List<({String tag, String url})>? _remoteLoaders;
  LoaderSupport? _support;

  @override
  void initState() {
    super.initState();
    _loadRemoteLoaders();
    _loadSupport();
  }

  Future<void> _loadRemoteLoaders() async {
    final releases = await LoaderLibrary.fetchReleases();
    if (!mounted) return;
    setState(() => _remoteLoaders = releases);
  }

  Future<void> _loadSupport() async {
    final support = await LoaderSupport.load();
    if (!mounted) return;
    setState(() => _support = support);
  }

  /// 某个 loader 版本能不能配当前游戏版本：true 支持 / false 不支持 / null 未知
  bool? _supported(String? loaderVersion) => _support?.supports(
    loaderVersion: loaderVersion,
    gameVersion: widget.gameVersion,
  );

  /// 兼容标注：兼容的第一个标「推荐」，明确不兼容的标出来（仍可选）
  String _compatibilityLabel(bool? supported, {required bool recommended}) {
    if (supported == true) return recommended ? '  ·  推荐' : '';
    if (supported == false) return '  ·  不支持当前游戏版本';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final screen = MediaQuery.of(context).size;
    final localVersions = LoaderLibrary.localVersions();
    final current = widget.currentLoaderPath == null
        ? null
        : p.normalize(widget.currentLoaderPath!);

    //版本高的排前面；库内的排在前（不用下载）
    final localJars = [...LoaderLibrary.list()]
      ..sort(
        (a, b) => LoaderLibrary.compareVersion(
          LoaderLibrary.versionOf(b),
          LoaderLibrary.versionOf(a),
        ),
      );
    final remoteOnly = [
      for (final release
          in _remoteLoaders ?? const <({String tag, String url})>[])
        if (!localVersions.contains(release.tag)) release,
    ]..sort((a, b) => LoaderLibrary.compareVersion(b.tag, a.tag));

    /// 下拉里的一项：`value` 直接放 [LoaderChoice]，选中即返回，省一层 key 映射
    final items = <({LoaderChoice choice, String label, IconData icon})>[];
    var recommending = true;
    var anySupported = false;
    LoaderChoice? currentChoice;

    //不用加载器（下载游戏时可以直接选原版启动）
    if (widget.allowNone) {
      items.add((
        choice: const LoaderChoice.none(),
        label: '不用加载器（原版启动）',
        icon: Icons.rocket_launch_outlined,
      ));
    }

    //库内已有的
    for (final jar in localJars) {
      final version = LoaderLibrary.versionOf(jar);
      final supported = _supported(version);
      if (supported == true) anySupported = true;
      final isRecommended = supported == true && recommending;
      if (isRecommended) recommending = false;
      final isCurrent = p.normalize(jar.path) == current;
      final choice = LoaderChoice.library(jar.path);
      if (isCurrent) currentChoice = choice;

      items.add((
        choice: choice,
        label:
            '${version ?? p.basename(jar.path)}'
            '（已下载${isCurrent ? '，当前在用' : ''}）'
            '${_compatibilityLabel(supported, recommended: isRecommended)}',
        icon: supported == false
            ? Icons.warning_amber_outlined
            : Icons.check_circle_outline,
      ));
    }

    //远程有、库里没有的
    for (final release in remoteOnly) {
      final supported = _supported(release.tag);
      if (supported == true) anySupported = true;
      final isRecommended = supported == true && recommending;
      if (isRecommended) recommending = false;
      items.add((
        choice: LoaderChoice.download(tag: release.tag, url: release.url),
        label:
            '${release.tag}（下载）'
            '${_compatibilityLabel(supported, recommended: isRecommended)}',
        icon: supported == false
            ? Icons.warning_amber_outlined
            : Icons.download,
      ));
    }

    final hasCandidate = localJars.isNotEmpty || remoteOnly.isNotEmpty;

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
              Text('选择 Copper 加载器', style: theme.textTheme.titleLarge),
              Text(
                widget.gameVersion == null
                    ? '最低兼容 Mindustry v${Mindustry.loaderMinRelease}；'
                          '库里已有的直接复用，不重复下载'
                    : '当前游戏版本 ${widget.gameVersion}；'
                          '库里已有的直接复用，不重复下载',
                style: theme.textTheme.bodySmall,
              ),
              //适配表里一个兼容的都没有：仍允许选，但先把话说清楚
              if (widget.gameVersion != null && hasCandidate && !anySupported)
                Text(
                  '适配表里没有标记兼容 ${widget.gameVersion} 的加载器，选了可能启动失败',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              //选项走 DropdownLayer：头部显示当前在用的 / 推荐的那个，点开再挑
              if (items.isNotEmpty)
                DropdownLayer<LoaderChoice>(
                  width: double.infinity,
                  initialValue: currentChoice ?? items.first.choice,
                  hintText: '选一个加载器',
                  menuHeight: 240,
                  onSelect: (choice) => Navigator.of(context).pop(choice),
                  options: [
                    for (final item in items)
                      DropdownOption(
                        value: item.choice,
                        label: item.label,
                        leading: Icon(item.icon, size: 18),
                      ),
                  ],
                ),
              if (_remoteLoaders == null)
                Text('正在查询远程版本…', style: theme.textTheme.bodySmall),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  IconTextButton(
                    icon: Icons.folder_open,
                    content: '选本地 jar…',
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const LoaderChoice.localFile()),
                  ),
                  IconTextButton(
                    icon: Icons.close,
                    content: '取消',
                    onTap: () => Navigator.of(context).pop(),
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
