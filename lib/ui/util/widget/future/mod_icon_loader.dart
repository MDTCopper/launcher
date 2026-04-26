import 'package:copperlauncher_main/data/net_asset.dart';
import 'package:copperlauncher_main/domain/task_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/constant/app_constant.dart';

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
  late var rope = 'https://raw.githubusercontent.com/${widget.modMeta.repo}';
  var mainBranches = ['main', 'master'];
  var icon = <String>['icon', 'assets/icon'];
  var format = <String>['png', 'jpg', 'jpeg'];

  @override
  void initState() {
    super.initState();
    _fetchIconUrl();
  }

  Future<String?> _fetchIconUrl() async {
    if (widget.modMeta.iconUrlCache != null) return widget.modMeta.iconUrlCache;
    for (final f in format) {
      for (final m in mainBranches) {
        for (final i in icon) {
          var url = '$rope/$m/$i.$f';
          try {
            final res = await dio.head(
              url,
              options: Options(
                headers: {
                  'User-Agent': 'MindustryModDownloader',
                  'Authorization': 'token $githubToken',
                },
              ),
            );
            if (res.data != null) {
              widget.modMeta.iconUrlCache = url;
              widget.modMeta.mainBranchCache = m;
              return url;
            }
          } catch (_) {
            continue;
          }
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _fetchIconUrl(),
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
                'Authorization': 'token $githubToken',
              },
              errorBuilder: (_, _, _) => onError,
            );
        }
      },
    );
  }
}
