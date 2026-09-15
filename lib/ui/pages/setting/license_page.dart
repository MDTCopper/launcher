import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/ui/components/animation/animated_expansion.dart';
import 'package:copper_launcher/ui/components/button/icon_text_button.dart';
import 'package:copper_launcher/ui/components/panel/content_panel_module.dart';
import 'package:copper_launcher/ui/components/panel/list_content_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 开源许可子路由（从「关于」页进入）
const licensePageRouteKey = '/setting/license';

/// 自研的开源许可页
///
/// 对应 Material 的 `showLicensePage`，但用项目自己的面板 / 展开组件渲染；
/// 数据仍来自 [LicenseRegistry]（Flutter 把各依赖的 LICENSE 汇总注册进去，
/// 见构建产物 NOTICES），所以依赖增减后不用手改。
///
/// 类名用 [OpenSourceLicensePage] 而非 `LicensePage`，避开 Material 同名 widget
class OpenSourceLicensePage extends StatefulWidget {
  const OpenSourceLicensePage({super.key});

  @override
  State<OpenSourceLicensePage> createState() => _OpenSourceLicensePageState();
}

class _OpenSourceLicensePageState extends State<OpenSourceLicensePage> {
  /// 包名 → 该包涉及的许可条目
  ///
  /// NOTICES 是把**同一份许可文本**的多个包并成一条，而同一个包又可能出现在多条里
  /// （一个包带多份内容不同的许可），所以直接按条目渲染会出现大量同名行；
  /// 这里按包归组，一个包一行（Material 的 LicensePage 也是这个口径）
  late final Future<Map<String, List<LicenseEntry>>> _grouped = _collect();

  static Future<Map<String, List<LicenseEntry>>> _collect() async {
    final entries = await LicenseRegistry.licenses.toList();

    final grouped = <String, List<LicenseEntry>>{};
    for (final entry in entries) {
      // 少数块没写包名：留个兜底分组，别把许可正文丢掉
      final packages = entry.packages.isEmpty
          ? const ['（未标注）']
          : entry.packages;
      for (final package in packages) {
        grouped.putIfAbsent(package, () => []).add(entry);
      }
    }

    final sorted = grouped.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Map.fromEntries(sorted);
  }

  /// 条目正文：段落按缩进层级铺开
  static String _paragraphsText(LicenseEntry entry) => entry.paragraphs
      .map((paragraph) => '${'    ' * paragraph.indent}${paragraph.text}')
      .join('\n\n');

  /// 一个包的多份许可拼成一段（内容不同，中间空行隔开）
  static String _packagesText(List<LicenseEntry> entries) =>
      entries.map(_paragraphsText).join('\n\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<Map<String, List<LicenseEntry>>>(
      future: _grouped,
      builder: (context, snapshot) {
        final grouped = snapshot.data;
        if (grouped == null) {
          // 载入态不套 ListContentPanel：它和下面的惰性列表是两套滚动容器，
          // 同一个 State 里来回换会让 ScrollController 短暂挂两个 position
          return const Center(child: Text('载入中…'));
        }

        return ListContentPanel(
          // 包很多（本项目约 250 个），给预测总长走惰性模块：只构建可见条目
          estimatedMaxScrollExtent: _estimatedExtent(context, grouped.length),
          items: [
            ContentPanelModule(
              title: '本项目',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Text('Copper Launcher 基于 MIT 许可证开源'),
                  IconTextButton(
                    icon: Icons.open_in_new,
                    content: '查看 LICENSE',
                    onTap: () async {
                      await launchUrl(
                        Uri.parse('$launcherRepoUrl/blob/main/LICENSE'),
                        mode: LaunchMode.inAppWebView,
                      );
                    },
                  ),
                ],
              ),
            ),
            ContentPanelModule(
              title: '第三方开源许可（${grouped.length} 个包）',
              child: Text('展开条目查看各包的许可正文'),
            ),
            for (final item in grouped.entries)
              AnimatedExpansion(
                title: Text(
                  item.value.length > 1
                      ? '${item.key}（${item.value.length} 份）'
                      : item.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                child: Text(
                  _packagesText(item.value),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }

  /// 惰性列表的滚动条预测总长（内容高 − 视口高）：折叠条目约 56 高，
  /// 展开后会更高——但滚动条到达边界会重校为真实值，估个量级即可
  static double _estimatedExtent(BuildContext context, int packageCount) {
    const moduleHeight = 140.0;
    const rowHeight = 56.0;
    const itemSpacing = 12.0;
    final content = moduleHeight * 2 + packageCount * (rowHeight + itemSpacing);
    return (content - MediaQuery.sizeOf(context).height).clamp(
      0.0,
      double.infinity,
    );
  }
}
