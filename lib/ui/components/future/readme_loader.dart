import 'dart:typed_data';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/ui/components/future/readme_view.dart';
import 'package:copper_launcher/ui/components/future/readme_source.dart';
import 'package:copper_launcher/ui/components/future/shields_badge.dart';
import 'package:copper_launcher/ui/components/scroll/desktop_scroll_view.dart';
import 'package:copper_launcher/ui/theme/app_colors.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';
import 'package:jovial_svg/jovial_svg.dart';

import '../../vars.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';

class ModNetReadmeLoader extends StatefulWidget {
  const ModNetReadmeLoader({super.key, required this.mod});

  final ModOfficialListEntry mod;
  @override
  State<StatefulWidget> createState() => _ModNetReadmeLoaderState();
}

class _ModNetReadmeLoaderState extends State<ModNetReadmeLoader> {
  //缓存
  static final Map<String, String> readmeDataMap = {};
  late final ScrollController controller;
  late final Future<String?> readme;

  @override
  void initState() {
    super.initState();
    controller = ScrollController();
    readme = fetchReadme();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<String?> fetchReadme() async {
    final mod = widget.mod;
    if (readmeDataMap[mod.repo]?.isNotEmpty ?? false) {
      return readmeDataMap[mod.repo];
    }

    final repo = 'https://raw.githubusercontent.com/${mod.repo}/';

    if (mod.mainBranchCache != null) {
      try {
        var url = '$repo${mod.mainBranchCache}/README.md';
        final res = await cio.get(url, headers: modDownloadHeaders);
        if (res.statusCode == 200) {
          readmeDataMap[mod.repo] = res.data.toString();
          return res.data.toString();
        }
      } catch (_) {}
    }

    final main = ['main', 'master'];
    for (var m in main) {
      try {
        var url = '$repo$m/README.md';
        final res = await cio.get(url, headers: modDownloadHeaders);

        if (res.statusCode != 200) continue;
        readmeDataMap[mod.repo] = res.data.toString();
        mod.mainBranchCache = m;
        return res.data.toString();
      } catch (_) {}
    }
    return null;
  }

  /// 弹窗外框：载入骨架与内容共用同一套尺寸与滚动容器，载入完成时不会跳一下
  Widget _buildFrame(Widget child) {
    final size = MediaQuery.of(context).size;

    return SizedBox(
      height: size.height * 0.75,
      width: size.width * 0.85,
      child: DesktopScrollViewContainer(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          physics: NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
          child: child,
        ),
      ),
    );
  }

  /// README 内容：交给自研渲染器（[ReadmeView]）
  Widget _buildContent(String? data) => _buildFrame(
    data == null
        ? Text('没有找到 README', style: Theme.of(context).textTheme.bodyLarge)
        : ReadmeView(data: data, source: ReadmeSource.ofMod(widget.mod)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final size = MediaQuery.of(context).size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Material(
            color: theme.colorScheme.secondaryContainer,
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: FutureBuilder(
                future: readme,
                builder: (_, s) {
                  switch (s.connectionState) {
                    case ConnectionState.none:
                    case ConnectionState.waiting:
                    case ConnectionState.active:
                      return _buildFrame(const ReadmeSkeleton());
                    case ConnectionState.done:
                      return _buildContent(s.data);
                  }
                },
              ),
            ),
          ),
          Positioned(
            top: 4,
            child: Container(
              height: 10,
              width: size.width * 0.85 - 4,
              alignment: Alignment.bottomCenter,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.secondaryContainer,
                    theme.colorScheme.secondaryContainer.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            child: Container(
              height: 10,
              width: size.width * 0.75 - 4,
              alignment: Alignment.bottomCenter,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    theme.colorScheme.secondaryContainer,
                    theme.colorScheme.secondaryContainer.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: ReboundButton(
              onTap: () {
                Navigator.pop(context);
              },
              child: Icon(Icons.arrow_back),
            ),
          ),
        ],
      ),
    );
  }
}

/// README 载入中的骨架：按 README 的常见结构摆占位块
/// （徽标行 / 标题 / 正文行 / 图片块），整体做缓慢的呼吸式明暗变化
///
/// 尺寸交给 [_ModNetReadmeLoaderState._buildFrame]，与内容共用一框，
/// 所以载入完成时不会先小后大地跳一下
class ReadmeSkeleton extends StatefulWidget {
  const ReadmeSkeleton({super.key});

  @override
  State<ReadmeSkeleton> createState() => ReadmeSkeletonState();
}

class ReadmeSkeletonState extends State<ReadmeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  /// 一条占位块（宽度不给就占满一行）
  Widget _bar(
    Color color, {
    double? width,
    double height = 12,
    double radius = 4,
  }) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  /// 一段正文：几行宽窄不一的占位行（宽度按可用的比例给）
  Widget _paragraph(Color color, List<double> widthFactors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        for (final factor in widthFactors)
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: factor,
            child: _bar(color),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    //骨架块用主题的次要提示色，两端透明度之间来回，深浅主题都成立
    final hint = AppColors.of(context).itemHint;

    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        final barColor = Color.lerp(
          hint.withAlpha(24),
          hint.withAlpha(72),
          Curves.easeInOut.transform(_breath.value),
        )!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            //顶部徽标行
            Row(
              spacing: 8,
              children: [
                _bar(barColor, width: 54, height: 20, radius: 10),
                _bar(barColor, width: 62, height: 20, radius: 10),
                _bar(barColor, width: 48, height: 20, radius: 10),
                _bar(barColor, width: 58, height: 20, radius: 10),
              ],
            ),
            //标题
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: 0.42,
              child: _bar(barColor, height: 24, radius: 6),
            ),
            _paragraph(barColor, const [1, 0.94, 0.98, 0.62]),
            //配图
            _bar(barColor, height: 120, radius: 8),
            _paragraph(barColor, const [1, 0.9, 0.55]),
            _bar(barColor, height: 96, radius: 8),
            _paragraph(barColor, const [1, 0.86, 0.7, 0.44]),
          ],
        );
      },
    );
  }
}

class ReadmeNetworkImage extends StatefulWidget {
  final Uri uri;

  /// 相对图片按哪个仓库解析
  final ReadmeSource source;
  final Widget? onLoading;
  final Widget? onError;
  final double? height;
  final double? width;
  const ReadmeNetworkImage({
    super.key,
    required this.uri,
    required this.source,
    this.height,
    this.width,
    this.onLoading,
    this.onError,
  });

  @override
  State<StatefulWidget> createState() => _ReadmeNetworkImageState();
}

class _ReadmeNetworkImageState extends State<ReadmeNetworkImage> {
  late final onError = widget.onError ?? Icon(Icons.broken_image_outlined);
  late final onLoading = widget.onLoading ?? CircularProgressIndicator();

  @override
  void initState() {
    super.initState();
    imageCache = _fetchImage();
  }

  @override
  void dispose() {
    imageCache.ignore();
    super.dispose();
  }

  late final Future<Widget?> imageCache;
  Future<Widget?> _fetchImage() async {
    final uri = widget.uri;

    // shields.io 徽章：优先用 JSON 数据自绘（样式无关、不依赖 SVG 引擎）
    if (uri.isAbsolute && uri.host.endsWith('shields.io')) {
      final badge = await _shieldsBadge(uri.toString());
      if (badge != null) return badge;
    }

    // 相对路径：按仓库解析（来源给的分支优先，再回退 main/master）；
    // 绝对路径：直接按 content-type 分流
    if (uri.isAbsolute) {
      return _byContentType(uri.toString());
    }

    final repo = 'https://raw.githubusercontent.com/${widget.source.repo}';
    final result = await _byContentType(
      '$repo/${widget.source.branch}/${uri.toString()}',
    );
    if (result != null) return result;

    for (final branch in ['main', 'master']) {
      if (branch == widget.source.branch) continue;
      final fallback = await _byContentType('$repo/$branch/${uri.toString()}');
      if (fallback != null) return fallback;
    }
    return null;
  }

  /// 按 content-type 决定渲染方式：栅格图走 cio 拉字节（代理与镜像可达），
  /// SVG 拉文本按 DPR 栅格化（见 [_svgToRaster]）
  Future<Widget?> _byContentType(String url) async {
    final isSvg = await _checkIsSvgFrom(url);
    if (isSvg == null) return null;

    if (isSvg) return _svgImage(url);
    return _raster(url);
  }

  /// shields.io 徽章：取 JSON 后自绘；任何一步失败都返回 null（回退 SVG 路径）
  Future<Widget?> _shieldsBadge(String url) async {
    try {
      final uri = Uri.parse(url);
      final res = await cio.get<String>(
        ShieldsBadge.jsonUrlOf(url),
        headers: modDownloadHeaders,
      );
      final body = res.statusCode == 200 ? res.data?.toString() : null;
      if (body == null) return null;
      final data = ShieldsBadge.parse(body);
      if (data == null) return null;

      return ShieldsBadge(
        data: data,
        style: uri.queryParameters['style'] ?? 'flat',
        logo: uri.queryParameters['logo'],
        logoColor: uri.queryParameters['logoColor'],
      );
    } catch (_) {
      return null;
    }
  }

  /// SVG：交给 jovial_svg 渲染。
  ///
  /// 之前用 flutter_svg，但它对**内嵌图像（base64 `<image>`）**、**属性继承
  /// （fill / font-size）**、**祖先 transform** 的支持都有缺口——徽章的徽标
  /// 渲染不出来、文字颜色错、字号被放大，只能靠逐个打补丁（fixSvgTextScale）。
  /// jovial_svg 这几项都支持，且是矢量渲染，无需自己按 DPR 栅格化
  Future<Widget?> _svgImage(String url) async {
    try {
      final res = await cio.get<String>(url, headers: modDownloadHeaders);
      final svg = res.statusCode == 200 ? res.data?.toString() : null;
      if (svg == null || svg.isEmpty) return null;

      final image = ScalableImage.fromSvgString(
        svg,
        // README 里的 SVG 常有引擎不支持的特性（滤镜、pattern 等），不打印告警
        warnF: (_) {},
      );
      // 预解码内嵌图像（徽标等）
      await image.prepareImages();

      return SizedBox(
        // 未指定尺寸时用 SVG 自身的视口尺寸，保证徽章按原始大小显示
        width: widget.width ?? image.width,
        height: widget.height ?? image.height,
        child: ScalableImageWidget(si: image),
      );
    } catch (_) {
      return null;
    }
  }

  /// 栅格图：走 cio（代理与镜像可达），不走 Image.network 直连
  Future<Widget?> _raster(String url) async {
    try {
      final res = await cio.get<Uint8List>(
        url,
        headers: modDownloadHeaders,
        responseType: ResponseType.bytes,
      );
      final data = res.data;
      if (res.statusCode != 200 || data == null || data.isEmpty) return null;
      return Image.memory(
        data,
        height: widget.height,
        width: widget.width,
        errorBuilder: (_, _, _) => onError,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _checkIsSvgFrom(String url) async {
    final res = await cio.head(url);
    if (res.statusCode != 200) return null;
    final type = res.headers.value('content-type');

    return switch (type) {
      'image/png' || 'image/jpeg' || 'image/gif' || 'image/webp' => false,
      'image/svg+xml;charset=utf-8' => true,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: imageCache,
      builder: (_, s) {
        if (s.hasError) return onError;
        return switch (s.connectionState) {
          ConnectionState.none => onError,
          ConnectionState.waiting || ConnectionState.active => onLoading,
          ConnectionState.done => s.data ?? onError,
        };
      },
    );
  }
}
