import 'package:copper_launcher/ui/dialog/custom_animated_dialog.dart';
import 'package:copper_launcher/ui/dialog/java_download_dialog.dart';
import 'package:copper_launcher/ui/util/route/page_key_provider.dart';
import 'package:copper_launcher/util/io/java/java_compat.dart';
import 'package:flutter/material.dart';

///缺 Java 提示：先弹确认弹窗，用户确认后再开「下载 Java」弹窗。
///
///[releaseInt] 游戏大版本，用来查推荐的 Java 版本；
///[context] 传自己的 context，不传则取 navigatorKey 的（启动任务没有自己的 context）。
///
///下载弹窗必须等确认弹窗自己收完再推：`showConfirmationPopup` 的 action 跑完后
///还会 pop 一次，同步推上去的下载弹窗会被它一并关掉。
void showJavaMissingPrompt({required int releaseInt, BuildContext? context}) {
  final targetContext = context ?? PageKeyProvider.navigatorKey.currentContext;
  if (targetContext == null || !targetContext.mounted) return;

  final recommendedVersion = JavaCompat.recommendedFor(releaseInt);

  showConfirmationPopup(
    context: targetContext,
    type: ConfirmationType.warning,
    title: '缺少 Java',
    content:
        '本机没有找到可用的 Java，游戏无法启动。\n'
        '可以现在下载一个（推荐 Java $recommendedVersion，装好会自动加入列表），'
        '也可以到「设置 - 启动」里手动添加已有的 Java。',
    action: () {
      //等确认弹窗自己收完再推下载弹窗，否则会被它随后那次 pop 一并关掉
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!targetContext.mounted) return;
        showJavaDownloadDialog(
          targetContext,
          recommendedVersion: recommendedVersion,
        );
      });
    },
  );
}
