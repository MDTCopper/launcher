import 'dart:io';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/ui/feature/images.dart';
import 'package:flutter/material.dart';

/// 版本图标：玩家换过的图优先，没换过回落品牌图（Copper / Mindustry）
class VersionIcon extends StatelessWidget {
  const VersionIcon({
    super.key,
    required this.version,
    this.height = 64,
    this.width,
    this.fallbackScale = 0.66,
    this.fit = BoxFit.contain,
  });

  final Mindustry version;
  final double height;
  final double? width;
  final double fallbackScale;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = version.resolvedIconPath;
    final file = path == null ? null : File(path);
    if (file != null && file.existsSync()) {
      return Image.file(
        file,
        height: height,
        width: width ?? height,
        fit: fit,
        errorBuilder: (_, _, _) => _brandIcon(),
      );
    }
    return _brandIcon();
  }

  Widget _brandIcon() => Image.asset(
    version.launcher == LauncherType.copper ? Images.copper : Images.mindustry,
    scale: fallbackScale,
    height: height,
    width: width,
    fit: fit,
  );
}
