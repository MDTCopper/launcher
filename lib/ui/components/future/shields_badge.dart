import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

import '../../vars.dart';

/// shields.io 徽章的数据（来自官方 JSON 端点）
class ShieldsBadgeData {
  const ShieldsBadgeData({
    required this.label,
    required this.message,
    required this.color,
    this.labelColor,
  });

  final String label;
  final String message;
  final String color;

  /// 左侧标签底色（对应 `labelColor` 参数）
  final String? labelColor;

  /// 颜色可能是名字（brightgreen / orange…）或十六进制（ff69b4、#ff69b4）
  Color get colorValue => _resolveColor(color) ?? const Color(0xFF007EC6);

  Color? get labelColorValue => labelColor == null ? null : _resolveColor(labelColor!);

  static Color? _resolveColor(String raw) {
    final value = raw.trim().toLowerCase().replaceFirst('#', '');
    const named = {
      'brightgreen': 0xFF44CC11,
      'success': 0xFF44CC11,
      'green': 0xFF97CA00,
      'yellowgreen': 0xFFA4A61D,
      'yellow': 0xFFDFB317,
      'orange': 0xFFFE7D37,
      'important': 0xFFFE7D37,
      'red': 0xFFE05D44,
      'critical': 0xFFE05D44,
      'blue': 0xFF007EC6,
      'informational': 0xFF007EC6,
      'grey': 0xFF9F9F9F,
      'gray': 0xFF9F9F9F,
      'lightgrey': 0xFF9F9F9F,
      'lightgray': 0xFF9F9F9F,
      'inactive': 0xFF9F9F9F,
      'blueviolet': 0xFF7852D6,
      'white': 0xFFFFFFFF,
      'black': 0xFF000000,
    };
    final known = named[value];
    if (known != null) return Color(known);
    final hex = value.length == 6 ? 'ff$value' : value;
    return int.tryParse(hex, radix: 16) == null ? null : Color(int.parse(hex, radix: 16));
  }
}

/// shields.io 徽章：不解析 SVG，用官方 JSON 数据自绘。
///
/// 为什么自绘：shields 会按样式（flat / for-the-badge / social…）生成结构
/// 各异的 SVG，靠 SVG 引擎逐个适配等于打地鼠；而 shields 提供 JSON 端点，
/// 只取 label / message / color 就能画出同样的徽章——矢量级清晰、颜色与
/// 字号完全可控，且不受 SVG 引擎能力限制
class ShieldsBadge extends StatelessWidget {
  const ShieldsBadge({
    super.key,
    required this.data,
    this.style = 'flat',
    this.logo,
    this.logoColor,
  });

  final ShieldsBadgeData data;

  /// flat / flat-square / plastic / for-the-badge / social
  final String style;

  /// simple-icons 的图标名（对应 URL 的 `logo=` 参数）
  final String? logo;
  final String? logoColor;

  /// 徽章 URL → JSON 端点：路径末尾换成 .json，query 原样保留
  ///
  /// 例：`.../github/stars/a/b?style=social` → `.../github/stars/a/b.json?style=social`
  static String jsonUrlOf(String url) {
    final queryIndex = url.indexOf('?');
    final path = queryIndex < 0 ? url : url.substring(0, queryIndex);
    final query = queryIndex < 0 ? '' : url.substring(queryIndex);

    final newPath = path.toLowerCase().endsWith('.svg')
        ? '${path.substring(0, path.length - 4)}.json'
        : '$path.json';
    return newPath + query;
  }

  /// 解析 shields 的 JSON（纯函数，便于测试）
  static ShieldsBadgeData? parse(String json) {
    String? field(String key) {
      final match = RegExp(
        '"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"',
      ).firstMatch(json);
      if (match == null) return null;
      return match
          .group(1)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\')
          .replaceAll(r'\/', '/');
    }

    final message = field('message');
    if (message == null) return null;
    return ShieldsBadgeData(
      label: field('label') ?? '',
      message: message,
      color: field('color') ?? 'blue',
      labelColor: field('labelColor'),
    );
  }

  bool get _isForTheBadge => style == 'for-the-badge';

  bool get _isSocial => style == 'social';

  @override
  Widget build(BuildContext context) {
    final height = _isForTheBadge ? 28.0 : 20.0;
    final radius = style == 'flat-square' ? 0.0 : 3.0;
    final fontSize = _isForTheBadge ? 10.0 : 11.0;
    final pad = _isForTheBadge ? 9.0 : 6.0;

    if (_isSocial) {
      // social：浅底 + 深色文字 + 彩色徽标，只显示数值（GitHub 式的计数胶囊）
      final logo = this.logo;
      return Container(
        height: height,
        padding: EdgeInsets.only(left: logo == null ? pad : 4, right: pad),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x14000000)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo != null) ...[
              _ShieldsLogo(
                slug: logo,
                color: logoColor == null ? data.colorValue : _parseHex(logoColor!),
              ),
              SizedBox(width: 4),
            ],
            Text(
              data.message,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.0,
                color: const Color(0xFF24292F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final foreground = _foregroundOf(data.colorValue);
    final labelBg = data.labelColorValue ?? const Color(0xFF555555);
    final showLabel = data.label.isNotEmpty;

    Widget segment(String text, Color background) => Container(
      padding: EdgeInsets.symmetric(horizontal: pad),
      color: background,
      alignment: Alignment.center,
      child: Text(
        _isForTheBadge ? text.toUpperCase() : text,
        style: TextStyle(
          color: foreground,
          fontSize: fontSize,
          height: 1.0,
          fontWeight: _isForTheBadge ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: _isForTheBadge ? 0.6 : 0,
        ),
      ),
    );

    final logo = this.logo;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLabel) segment(data.label, labelBg),
            if (logo != null)
              Container(
                color: data.colorValue,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _ShieldsLogo(
                  slug: logo,
                  color: logoColor == null ? foreground : _parseHex(logoColor!),
                ),
              ),
            segment(data.message, data.colorValue),
          ],
        ),
      ),
    );
  }

  /// 依据背景亮度选前景色（模仿 shields 的自动对比色）
  static Color _foregroundOf(Color background) =>
      background.computeLuminance() > 0.5
          ? const Color(0xFF333333)
          : const Color(0xFFFFFFFF);

  static Color _parseHex(String raw) =>
      ShieldsBadgeData._resolveColor(raw) ?? const Color(0xFFFFFFFF);
}

/// simple-icons 徽标：SVG 是单路径，交给 jovial_svg 渲染即可（单色，可着色）
class _ShieldsLogo extends StatefulWidget {
  const _ShieldsLogo({required this.slug, required this.color});

  final String slug;
  final Color color;

  @override
  State<_ShieldsLogo> createState() => _ShieldsLogoState();
}

/// 徽标缓存（同一图标只取一次）
final Map<String, Future<ScalableImage?>> _logoCache = {};

class _ShieldsLogoState extends State<_ShieldsLogo> {
  late final Future<ScalableImage?> _future = _load();

  Future<ScalableImage?> _load() => _logoCache.putIfAbsent(widget.slug, () async {
    try {
      final res = await cio.get<String>(
        'https://cdn.simpleicons.org/${widget.slug}',
        headers: modDownloadHeaders,
      );
      final svg = res.statusCode == 200 ? res.data?.toString() : null;
      if (svg == null || svg.isEmpty) return null;
      return ScalableImage.fromSvgString(svg, warnF: (_) {});
    } catch (_) {
      return null;
    }
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ScalableImage?>(
      future: _future,
      builder: (_, s) {
        final image = s.data;
        if (image == null) return const SizedBox.shrink();
        return ColorFiltered(
          colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
          child: SizedBox(
            width: 14,
            height: 14,
            child: ScalableImageWidget(si: image),
          ),
        );
      },
    );
  }
}
