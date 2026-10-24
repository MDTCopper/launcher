import 'package:copper_launcher/data/net/mdtbbs/mdtbbs_config.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 用户头像：有 `avatar_url` 就加载，没有 / 加载失败退回一个圆底图标
///
/// BBS 的 `/me` 与好友在线聚合都带 `avatar_url`（论坛那头叫 `avatar_url`），
/// 之前一直没显示，列表里全是同一个默认图标
class UserAvatar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.lowBackgroundOnCard,
        shape: BoxShape.circle,
      ),
      child: Icon(fallbackIcon, size: size * 0.6, color: colors.itemSecondary),
    );
    final source = url;
    if (source == null || source.isEmpty) return fallback;
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
            child: Image.network(
              // 服务端给的是站内相对路径（`/uploads/avatars/...`），得补成完整地址
              MdtbbsConfig.resolveUrl(source),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
          ),
        ),
      ),
    );
  }
}
