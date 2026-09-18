import 'package:copper_launcher/ui/components/rebound/rebound_container.dart';
import 'package:flutter/material.dart';

import '../../../core/app_config.dart';

///页内警告条：一句话提示 + 跳转按钮 + 关闭按钮
///
///[onNavigate] 跳转按钮的去处（一般是相关设置页），**不给就不显示那个按钮**，
///免得页面上留一个点了没反应的箭头；[onTap] 是关闭后额外要做的事（如原地刷新
///把这条从列表里摘掉），关闭本身由这里写配置
Widget? buildWarningBar(
  BuildContext context,
  String key,
  String message, {
  VoidCallback? onTap,
  VoidCallback? onNavigate,
}) {
  final setting = config.setting.getCustomSetting(key, true);
  if (setting == false) return null;
  final theme = Theme.of(context);
  return Container(
    decoration: BoxDecoration(
      color: theme.colorScheme.primary.withAlpha(40),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: theme.colorScheme.primary.withAlpha(100),
        width: 2,
      ),
    ),
    padding: EdgeInsets.all(4),
    child: Row(
      children: [
        Expanded(child: Text(message, maxLines: 2)),
        if (onNavigate != null) ...[
          ReboundContainer(
            backgroundColor: Colors.transparent,
            pressedScale: 0.75,
            borderRadius: BorderRadius.circular(4),
            onTap: onNavigate,
            child: Icon(Icons.arrow_outward_outlined),
          ),
          SizedBox(width: 4),
        ],
        ReboundContainer(
          backgroundColor: Colors.transparent,
          pressedScale: 0.75,
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            config.setting.customSetting[key] = false;
            config.save();
            onTap?.call();
          },
          child: Icon(Icons.close),
        ),
      ],
    ),
  );
}
