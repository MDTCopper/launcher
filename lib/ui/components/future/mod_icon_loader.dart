import 'package:copper_launcher/data/net_asset.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:flutter/material.dart';

class ModNetworkIcon extends StatefulWidget {
  final ModOfficialListMeta modMeta;
  final double size;
  final Widget? onWaiting;
  final Widget? onError;

  const ModNetworkIcon({
    super.key,
    required this.modMeta,
    this.size = 64,
    this.onWaiting,
    this.onError,
  });

  @override
  State<StatefulWidget> createState() => _ModNetworkIconState();
}

class _ModNetworkIconState extends State<ModNetworkIcon> {
  /// 探测候选：分支 × 路径 × 后缀，命中第一个就停
  static const _branchCandidates = ['main', 'master'];
  static const _pathCandidates = ['icon', 'assets/icon'];
  static const _formatCandidates = ['png', 'jpg', 'jpeg'];

  /// 探测图标地址的 Future，只建一次
  ///
  /// 原来直接在 build 里调 `_fetchIconUrl()`，每次重建都新建 Future、重跑整轮
  /// HEAD 探测；模组页一页 25 个 tile 而且都是常驻的，任何 setState（改筛选、
  /// 翻页、选择）都会放大成几百次请求
  late Future<String?> _iconUrlFuture;

  @override
  void initState() {
    super.initState();
    _iconUrlFuture = _fetchIconUrl();
  }

  @override
  void didUpdateWidget(covariant ModNetworkIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 翻页 / 改筛选时同一位置的 element 会换到另一个 mod，得重新探测
    if (oldWidget.modMeta != widget.modMeta) {
      _iconUrlFuture = _fetchIconUrl();
    }
  }

  Future<String?> _fetchIconUrl() async {
    final meta = widget.modMeta;

    if (meta.iconUrlCache != null) return meta.iconUrlCache;
    // 探过且确认没有图标：直接返回，别再跑一轮
    if (meta.iconMissingCache) return null;

    final repoUrl = 'https://raw.githubusercontent.com/${meta.repo}';
    for (final format in _formatCandidates) {
      for (final branch in _branchCandidates) {
        for (final path in _pathCandidates) {
          final url = '$repoUrl/$branch/$path.$format';
          try {
            final res = await cio.head(url, headers: modDownloadHeaders);
            if (res.data != null) {
              meta.iconUrlCache = url;
              meta.mainBranchCache = branch;
              return url;
            }
          } catch (_) {
            continue;
          }
        }
      }
    }

    meta.iconMissingCache = true;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _iconUrlFuture,
      builder: (_, s) {
        if (s.hasError) {
          return widget.onError ??
              Icon(Icons.broken_image_outlined, size: widget.size * 0.5);
        }

        final onWaiting =
            widget.onWaiting ??
            CircularProgressIndicator(
              padding: EdgeInsets.all(widget.size * 0.25),
            );

        final onError =
            widget.onError ??
            Icon(Icons.broken_image_outlined, size: widget.size * 0.5);

        switch (s.connectionState) {
          case ConnectionState.none:
          case ConnectionState.active:
          case ConnectionState.waiting:
            return onWaiting;
          case ConnectionState.done:
            if (!s.hasData) {
              return onError;
            }
            return Image.network(
              s.data!,
              height: widget.size,
              width: widget.size,
              headers: {
                'User-Agent': 'MindustryModDownloader',
              },
              errorBuilder: (_, _, _) => onError,
            );
        }
      },
    );
  }
}
