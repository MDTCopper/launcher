import 'package:copperlauncher_main/ui/util/widget/rebound_container.dart';
import 'package:flutter/material.dart';

import '../../../core/app_config.dart';

Widget? buildWarningBar(
  BuildContext context,
  String key,
  String message, {
  VoidCallback? onTap,
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
        ReboundContainer(
          backgroundColor: Colors.transparent,
          pressedScale: 0.75,
          borderRadius: BorderRadius.circular(4),
          onTap: () {},
          child: Icon(Icons.arrow_outward_outlined),
        ),
        SizedBox(width: 4),
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
