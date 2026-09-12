import 'dart:typed_data';

import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/ui/components/future/mod_icon_loader.dart';
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

    // shields.io 徽章：统一转成 PNG 端点。flutter_svg 对徽章文字（transform
    // scale + 字距）渲染不可靠，fixSvgTextScale 只是部分缓解，服务端栅格化最稳。
    // 很多徽章 URL 没有后缀（/badge/…、/static/v1?…、/github/downloads/…?…），
    // 所以是「替换或追加 .png」，query 保持不变
    if (uri.host.contains('img.shields.io')) {
      return _raster(ModNetworkIcon.shieldsPngUrl(uri.toString()));
    }

    String url;
    if (uri.isAbsolute) {
      url = uri.toString();
      return _byContentType(url);
    }

    // 相对路径：按仓库解析（缓存的分支优先，再回退 main/master）
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
  /// SVG 拉文本做 transform 修正后交给 flutter_svg
  Future<Widget?> _byContentType(String url) async {
    final isSvg = await _checkIsSvgFrom(url);
    if (isSvg == null) return null;

    if (isSvg) {
      try {
        final res = await cio.get<String>(url, headers: modDownloadHeaders);
        if (res.statusCode != 200) return null;
        return SvgPicture.string(
          fixSvgTextScale(res.data.toString()),
          height: widget.height,
          width: widget.width,
          errorBuilder: (_, _, _) => onError,
        );
      } catch (_) {
        return null;
      }
    }
    return _raster(url);
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
