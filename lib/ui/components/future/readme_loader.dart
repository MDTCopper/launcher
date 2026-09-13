import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/ui/components/future/mod_readme_view.dart';
import 'package:copper_launcher/ui/components/scroll/desktop_scroll_view.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../vars.dart';
import 'package:copper_launcher/ui/components/button/rebound_button.dart';

class ModNetReadmeLoader extends StatefulWidget {
  const ModNetReadmeLoader({super.key, required this.mod});

  final ModOfficialListMeta mod;
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
        final res = await cio.get(
          url,
          headers: modDownloadHeaders,
        );
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
        final res = await cio.get(
          url,
          headers: modDownloadHeaders,
        );

        if (res.statusCode != 200) continue;
        readmeDataMap[mod.repo] = res.data.toString();
        mod.mainBranchCache = m;
        return res.data.toString();
      } catch (_) {}
    }
    return null;
  }

  /// README 内容：交给自研渲染器（[ModReadmeView]）
  Widget _buildContent(String? data) {
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
          child: data == null
              ? Text('没有找到 README', style: Theme.of(context).textTheme.bodyLarge)
              : ModReadmeView(data: data, mod: widget.mod),
        ),
      ),
    );
  }

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
                      return SizedBox(
                        width: 100,
                        height: 100,
                        child: Text('载入中'),
                      );
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

class ModReadmeNetworkImage extends StatefulWidget {
  final Uri uri;
  final ModOfficialListMeta mod;
  final Widget? onLoading;
  final Widget? onError;
  final double? height;
  final double? width;
  const ModReadmeNetworkImage({
    super.key,
    required this.uri,
    required this.mod,
    this.height,
    this.width,
    this.onLoading,
    this.onError,
  });

  @override
  State<StatefulWidget> createState() => _ModReadmeNetworkImageState();
}

class _ModReadmeNetworkImageState extends State<ModReadmeNetworkImage> {
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

    // 相对路径：按仓库解析（缓存的分支优先，再回退 main/master）；
    // 绝对路径：直接按 content-type 分流
    if (uri.isAbsolute) {
      return _byContentType(uri.toString());
    }

    final repo = 'https://raw.githubusercontent.com/${widget.mod.repo}';
    if (widget.mod.mainBranchCache != null) {
      final result = await _byContentType(
        '$repo/${widget.mod.mainBranchCache}/${uri.toString()}',
      );
      if (result != null) return result;
    }
    for (final branch in ['main', 'master']) {
      final result = await _byContentType('$repo/$branch/${uri.toString()}');
      if (result != null) return result;
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

  /// SVG：按 DPR 栅格化后，**按逻辑尺寸显示**
  ///
  /// 位图分辨率高于显示尺寸所以在高分屏依然清晰；但显示尺寸必须用逻辑尺寸
  /// ——否则位图会按像素 1:1 铺开，在 DPI>100% 时整个徽章被放大（字变得超大）
  Future<Widget?> _svgImage(String url) async {
    ui.Picture? sourcePicture;
    ui.Image? image;
    // DPR 在异步间隙前取好（避免跨 async 使用 BuildContext）
    final scale = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    try {
      final res = await cio.get<String>(url, headers: modDownloadHeaders);
      if (res.statusCode != 200) return null;

      final pictureInfo = await vg.loadPicture(
        SvgStringLoader(fixSvgTextScale(res.data.toString())),
        null,
      );
      sourcePicture = pictureInfo.picture;

      final width = (pictureInfo.size.width * scale).ceil();
      final height = (pictureInfo.size.height * scale).ceil();
      if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
        return null;
      }

      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(scale)
        ..drawPicture(sourcePicture);
      image = await recorder.endRecording().toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null) return null;

      return Image.memory(
        bytes,
        // 显示尺寸取逻辑尺寸；HTML 的 width/height 属性优先
        width: widget.width ?? pictureInfo.size.width,
        height: widget.height ?? pictureInfo.size.height,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => onError,
      );
    } catch (_) {
      return null;
    } finally {
      sourcePicture?.dispose();
      image?.dispose();
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
