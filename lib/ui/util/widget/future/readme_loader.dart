import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:copperlauncher_main/ui/util/widget/desktop_scroll_view.dart';
import 'package:copperlauncher_main/util/format/string_cleaner.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../util/io/downloader.dart';
import '../../../vars.dart';
import '../feature_button.dart';

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
        final res = await dio.get(
          url,
          options: Options(headers: modDownloadHeaders),
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
        print(url);
        final res = await dio.get(
          url,
          options: Options(headers: modDownloadHeaders),
        );

        if (res.statusCode != 200) continue;
        readmeDataMap[mod.repo] = res.data.toString();
        mod.mainBranchCache = m;
        return res.data.toString();
      } catch (_) {}
    }
    return null;
  }

  Widget _buildHtml(String? data) {
    final size = MediaQuery.of(context).size;

    return SizedBox(
      height: size.height * 0.75,
      width: size.width * 0.85,
      child: DesktopScrollViewContainer(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          physics: NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              SizedBox(height: 28),
              Html(
                data: data,
                shrinkWrap: true,
                style: {
                  'hr': Style(
                    margin: Margins.only(top: 6, bottom: 2),
                    height: Height(1),
                  ),
                },
                extensions: [
                  ImageExtension(
                    assetSchema: '',
                    builder: (c) {
                      final url = c.attributes['src'] ?? '';

                      final width =
                          c.attributes['width'] != null
                              ? double.parse(c.attributes['width']!)
                              : null;

                      final height =
                          c.attributes['height'] != null
                              ? double.parse(c.attributes['height']!)
                              : null;

                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: size.width * 0.75,
                          maxHeight: size.height * 0.6,
                        ),
                        child: ModReadmeNetworkImage(
                          uri: Uri.parse(url),
                          mod: widget.mod,
                          width: width,
                          height: height,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
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
                      final h = md.markdownToHtml(
                        s.data ?? 'wu',
                        extensionSet: md.ExtensionSet.gitHubFlavored,
                      );
                      print(h);
                      return _buildHtml(h);
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
    //特别处理img.shields.io
    final uri = widget.uri;
    if (widget.uri.host.contains('img.shields.io')) {
      try {
        final res = await dio.getUri(
          uri,
          options: Options(headers: gameDownloadHeaders),
        );
        if (res.statusCode != 200) return null;
        return SvgPicture.string(
          fixSvgTextScale(res.data),
          errorBuilder: (_, _, _) => onError,
        );
      } catch (_) {
        return null;
      }
    }

    String url;
    if (uri.isAbsolute) {
      url = uri.toString();
      var isSvg = await _checkIsSvgFrom(url);
      if (isSvg == null) return null;
      if (isSvg) {
        return SvgPicture.network(
          url,
          allowDrawingOutsideViewBox: true,
          height: widget.height,
          width: widget.width,
          errorBuilder: (_, _, _) => onError,
        );
      } else {
        return Image.network(
          url,
          height: widget.height,
          width: widget.width,
          errorBuilder: (_, _, _) => onError,
        );
      }
    } else {
      final repo = 'https://raw.githubusercontent.com/${widget.mod.repo}';

      if (widget.mod.mainBranchCache != null) {
        try {
          url = '$repo/${widget.mod.mainBranchCache}/${uri.toString()}';
          var isSvg = await _checkIsSvgFrom(url);
          if (isSvg != null) {
            if (isSvg) {
              return SvgPicture.network(
                url,
                height: widget.height,
                width: widget.width,
                errorBuilder: (_, _, _) => onError,
              );
            } else {
              return Image.network(
                url,
                height: widget.height,
                width: widget.width,
                errorBuilder: (_, _, _) => onError,
              );
            }
          }
        } catch (_) {}
      }

      for (var branch in ['main', 'master']) {
        try {
          url = '$repo$branch/${uri.toString()}';
          print(url);
          var isSvg = await _checkIsSvgFrom(url);
          if (isSvg == null) continue;
          if (isSvg) {
            return SvgPicture.network(
              url,
              height: widget.height,
              width: widget.width,
              theme: SvgTheme(xHeight: 100),
              errorBuilder: (_, _, _) => onError,
            );
          } else {
            return Image.network(
              url,
              height: widget.height,
              width: widget.width,
              errorBuilder: (_, _, _) => onError,
            );
          }
        } catch (_) {}
      }
      return null;
    }
  }

  Future<bool?> _checkIsSvgFrom(String url) async {
    final res = await dio.head(url);
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
    final theme = Theme.of(context);

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
