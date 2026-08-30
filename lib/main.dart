import 'dart:io';

import 'package:copper_launcher/core/app_config.dart';
import 'package:copper_launcher/data/local_asset.dart';
import 'package:copper_launcher/ui/copper_launcher.dart';
import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/app_paths.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/io/token_encryptor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

void main() async {
  await _initialize();
  runCopperLauncher();
}

Future<void> _initialize() async {
  _checkPlatform();
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  await TokenEncryptor.init();
  await initAppConfig();
  await Log.init();
  await _checkAndPromptGameIssues();
  await _initViewPool();
}

void _checkPlatform() {
  if (kIsWeb) throw Exception('Web不支持');
  if (Platform.isIOS) throw Exception('IOS平台不支持');
}

Future _initViewPool() async {
  if (Platform.isAndroid) {
    await _initAndroidView();
  } else {
    await _initWindows();
  }
}

Future<void> _initWindows() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(880, 495),
    // 移动端尺寸 Size(760, 360),
    minimumSize: Size(760, 450),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> _initAndroidView() async {
  // 设置屏幕方向为横屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  //隐藏状态栏和导航栏
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

/// 启动检查：缺失目录/版本收集起来，引用检测出孤儿本体，一并询问是否删除
Future<void> _checkAndPromptGameIssues() async {
  final folds = config.versionOptions.versionFolds;

  final missingFolds = <VersionFold>[];
  final missingVersions = <Mindustry>[];
  for (final fold in folds) {
    if (!await Directory(fold.path).exists()) {
      missingFolds.add(fold);
      Log.add(.warning, '游戏目录不存在: [${fold.tag}] ${fold.path}');
      continue;
    }
    for (final version in fold.versions) {
      if (!await File(version.jarPath).exists()) {
        missingVersions.add(version);
        Log.add(.warning, '游戏版本缺少 jar: [${version.tag}] ${version.jarPath}');
      }
    }
  }

  // 引用检测
  final brokenLower = <String>{
    for (final fold in missingFolds)
      for (final version in fold.versions)
        p.normalize(version.jarPath).toLowerCase(),
    for (final version in missingVersions)
      p.normalize(version.jarPath).toLowerCase(),
  };
  final survivingLower = <String>{
    for (final fold in folds)
      for (final version in fold.versions)
        p.normalize(version.jarPath).toLowerCase(),
  }..removeAll(brokenLower);

  final orphanJars = <String>[];
  final seenOrphan = <String>{};
  void considerOrphan(String jarPath) {
    final norm = p.normalize(jarPath).toLowerCase();
    if (seenOrphan.add(norm) &&
        !survivingLower.contains(norm) &&
        File(jarPath).existsSync()) {
      orphanJars.add(jarPath);
    }
  }

  for (final fold in missingFolds) {
    for (final version in fold.versions) {
      considerOrphan(version.jarPath);
    }
  }
  for (final version in missingVersions) {
    considerOrphan(version.jarPath);
  }

  final count =
      missingFolds.length + missingVersions.length + orphanJars.length;
  if (count == 0) return;

  // 应用首帧后几秒：检查缺失目录 / 版本 + 引用检测，有缺失则询问是否删除
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(seconds: 3), () {
      final navContext = PageKeyProvider.navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;
      final detail = [
        for (final fold in missingFolds) '目录 [${fold.tag}] 已不存在',
        for (final version in missingVersions) '版本 [${version.tag}] 缺少 jar',
        for (final jar in orphanJars) '无引用本体: $jar',
      ].join('\n');
      showConfirmationPopup(
        context: navContext,
        type: ConfirmationType.warning,
        title: '检测到缺失或被孤立的游戏文件',
        content:
            '以下记录或文件是否删除？\n$detail\n\n'
            '（缺失记录仅删记录；无引用本体将删除文件）',
        action: () async {
          for (final fold in missingFolds) {
            config.versionOptions.versionFolds.remove(fold);
            Log.add(.info, '已删除缺失目录记录: [${fold.tag}]');
          }
          for (final version in missingVersions) {
            for (final fold in config.versionOptions.versionFolds) {
              fold.versions.remove(version);
            }
            Log.add(.info, '已删除缺失版本记录: [${version.tag}]');
          }
          for (final jar in orphanJars) {
            try {
              await File(jar).delete();
              Log.add(.info, '已删除无引用本体: $jar');
            } catch (e) {
              Log.add(.warning, '删除无引用本体失败: $jar $e');
            }
          }
          await config.save();
        },
      );
    });
  });
}
