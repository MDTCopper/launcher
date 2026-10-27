import 'dart:io';

import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/io/avatar_cache.dart';
import 'package:flutter/material.dart';

/// 用户头像：有 `avatar_url` 就加载（**落盘缓存**，下次启动秒出），
/// 没有 / 加载失败退回一个圆底图标
///
/// BBS 的 `/me` 与好友在线聚合都带 `avatar_url`（站内相对路径，要按 [MdtbbsConfig.resolveUrl] 补全）
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    this.url,
    this.size = 28,
    this.fallbackIcon = Icons.person,
  });

  final String? url;
  final double size;
  final IconData fallbackIcon;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  void _resolve() {
    final raw = widget.url;
    if (raw == null || raw.isEmpty) {
      _file = null;
      return;
    }
    final url = _sized(MdtbbsConfig.resolveUrl(raw), widget.size);
    final cached = AvatarCache.cached(url);
    if (cached != null) {
      _file = cached;
      return;
    }
    _file = null;
    AvatarCache.load(url).then((file) {
      if (!mounted || file == null) return;
      setState(() => _file = file);
    });
  }

  /// 服务端支持 ?size=32|64|128 的 WebP 缩略图，列表里别拉原图
  static String _sized(String url, double size) {
    if (url.contains('?size=')) return url;
    final bucket = size <= 32
        ? 32
        : size <= 64
        ? 64
        : 128;
    return '$url?size=$bucket';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final size = widget.size;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.lowBackgroundOnCard,
        shape: BoxShape.circle,
      ),
      child: Icon(
        widget.fallbackIcon,
        size: size * 0.6,
        color: colors.itemSecondary,
      ),
    );
    final file = _file;
    if (file == null) return fallback;
    // FittedBox 兜住父级的挤压：不然高度被压小、ClipOval 就成了椭圆
    return SizedBox(
      width: size,
      height: size,
      child: FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
          ),
        ),
      ),
    );
  }
}
