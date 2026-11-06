import 'dart:io';

import 'package:copper_launcher/ui/pages/design/template_skin.dart';
import 'package:flutter/material.dart';

/// 图片位：固定尺寸的圆角方框，图没到 / 加载失败时退回图标
///
/// 用于模组图标、版本图标、地图封面这类「有图就用图、没有就占位」的位置。
/// 只支持本地文件与网络图（设计层不引资源包）；`image == null` 时直接显示 [icon]
class TemplateImageBox extends StatelessWidget {
  const TemplateImageBox({
    super.key,
    required this.skin,
    required this.size,
    this.image,
    this.icon = Icons.image_outlined,
    this.radius,
    this.padding = 0,
  });

  final TemplateSkin skin;
  final double size;

  /// 本地文件路径或 http(s) 地址
  final String? image;
  final IconData icon;
  final double? radius;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: skin.sunken,
        borderRadius: BorderRadius.circular(radius ?? TemplateRadius.card),
      ),
      child: image == null
          ? Icon(icon, size: size * 0.42, color: skin.textTertiary)
          : ClipRRect(
              borderRadius: BorderRadius.circular(
                (radius ?? TemplateRadius.card) - padding,
              ),
              child: _buildImage(),
            ),
    );
    return box;
  }

  Widget _buildImage() {
    final path = image!;
    final fallback = Icon(icon, size: size * 0.42, color: skin.textTertiary);
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(child: fallback),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Center(child: fallback),
    );
  }
}

/// 头像：圆形，图缺失时用名字首字 / 图标兜底
class TemplateAvatar extends StatelessWidget {
  const TemplateAvatar({
    super.key,
    required this.skin,
    required this.size,
    this.image,
    this.name,
    this.icon = Icons.person_outline,
  });

  final TemplateSkin skin;
  final double size;
  final String? image;

  /// 有名字时取首字（中文取一个字，英文取首字母大写）
  final String? name;
  final IconData icon;

  String? get _initial {
    final text = name?.trim();
    if (text == null || text.isEmpty) return null;
    final first = text.characters.first;
    return first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initial;
    final placeholder = initial == null
        ? Icon(icon, size: size * 0.5, color: skin.textTertiary)
        : Text(
            initial,
            style: TemplateType.item.copyWith(
              color: skin.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: size * 0.4,
            ),
          );

    if (image == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: skin.sunken, shape: BoxShape.circle),
        child: placeholder,
      );
    }
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(image!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            alignment: Alignment.center,
            color: skin.sunken,
            child: placeholder,
          ),
        ),
      ),
    );
  }
}
