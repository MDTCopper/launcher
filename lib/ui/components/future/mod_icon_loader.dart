import 'dart:typed_data';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 图标加载结果：把「确认没有图标」和「网络失败」分开
///
/// 两者在 UI 上要给不同的占位，且**网络失败不能写入缺失缓存**——
/// 否则一次网络抖动会把图标永久判定为缺失（直到重启）
enum ModIconResultType { found, missing, networkError }

class ModIconResult {
  final ModIconResultType type;

  /// [ModIconResultType.found] 时有效：图标地址
  final String? url;

  /// [ModIconResultType.found] 时有效：已经由 cio 拉到的图片字节
  final Uint8List? bytes;

  const ModIconResult._(this.type, [this.url, this.bytes]);

  const ModIconResult.found(String url, [Uint8List? bytes])
    : this._(ModIconResultType.found, url, bytes);

  const ModIconResult.missing() : this._(ModIconResultType.missing);

  const ModIconResult.networkError() : this._(ModIconResultType.networkError);
}

class ModNetworkIcon extends StatefulWidget {
  final ModOfficialListEntry modMeta;
  final double size;

  /// 载入中占位（默认转圈）
  final Widget? onWaiting;

  /// 该模组确实没有图标（官方列表标记无图标 / 图标文件不存在）时的占位
  final Widget? onMissing;

  /// 网络失败（断网 / 代理不通）时的占位，可与「没有图标」区分显示
  final Widget? onNetworkError;

  const ModNetworkIcon({
    super.key,
    required this.modMeta,
    this.size = 64,
    this.onWaiting,
    this.onMissing,
    this.onNetworkError,
  });

  @override
  State<StatefulWidget> createState() => _ModNetworkIconState();
}

class _ModNetworkIconState extends State<ModNetworkIcon> {
  /// 图标加载的 Future，只建一次
  late Future<ModIconResult> _iconFuture;

  @override
  void initState() {
    super.initState();
    _iconFuture = _loadIcon();
  }

  @override
  void didUpdateWidget(covariant ModNetworkIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 翻页 / 改筛选时同一位置的 element 会换到另一个 mod，得重新加载
    if (oldWidget.modMeta != widget.modMeta) {
      _iconFuture = _loadIcon();
    }
  }

  /// 取官方列表托管好的图标字节，给出三态结果
  ///
  /// 官方列表已经标好有没有图标、图标地址也固定，不必再逐分支逐路径 HEAD；
  /// 字节仍**必须走 cio**（代理 / 镜像可达），raw 在部分网络下直连不通。
  /// 正常命中与「本来没有图标」都不记日志，只有网络 / 响应异常才 warning
  Future<ModIconResult> _loadIcon() async {
    final meta = widget.modMeta;

    if (meta.iconMissingCache) return const ModIconResult.missing();
    // 官方列表说没有图标就不发请求
    if (meta.hasIcon == false) {
      meta.iconMissingCache = true;
      return const ModIconResult.missing();
    }

    final url = meta.iconUrlCache ?? meta.officialIconUrl;
    try {
      final res = await cio.get<Uint8List>(
        url,
        headers: modDownloadHeaders,
        responseType: ResponseType.bytes,
      );
      final data = res.data;
      if (res.statusCode == 200 && data != null && data.isNotEmpty) {
        meta.iconUrlCache = url;
        return ModIconResult.found(url, data);
      }
      addLog(
        .warning,
        '图标响应异常（HTTP ${res.statusCode}）：${meta.repo}',
        tag: 'ModIcon',
      );
      return const ModIconResult.networkError();
    } on DioException catch (e) {
      // 列表与图标文件不同步时按缺失处理；网络问题不写缺失缓存
      if (e.response?.statusCode == 404) {
        meta.iconMissingCache = true;
        return const ModIconResult.missing();
      }
      addLog(
        .warning,
        '图标加载失败：${meta.repo}'
        '（${e.type.name}：${removeNewlines(e.message ?? '')}）',
        tag: 'ModIcon',
      );
      return const ModIconResult.networkError();
    } catch (e) {
      addLog(
        .warning,
        '图标加载失败：${meta.repo}（${removeNewlines('$e')}）',
        tag: 'ModIcon',
      );
      return const ModIconResult.networkError();
    }
  }

  Widget _defaultPlaceholder(IconData icon, {Color? color}) => Icon(
    icon,
    size: widget.size * 0.5,
    color: color ?? Theme.of(context).colorScheme.outline,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onWaiting =
        widget.onWaiting ??
        CircularProgressIndicator(padding: EdgeInsets.all(widget.size * 0.25));
    //没有图标：中性（该模组就是没放图标）
    final onMissing =
        widget.onMissing ?? _defaultPlaceholder(Icons.extension_outlined);
    //网络失败：警示色，与「没有图标」拉开差距
    final onNetworkError =
        widget.onNetworkError ??
        _defaultPlaceholder(Icons.cloud_off_outlined, color: scheme.error);

    return FutureBuilder<ModIconResult>(
      future: _iconFuture,
      builder: (_, s) {
        if (s.hasError) return onNetworkError;
        if (s.connectionState != ConnectionState.done) return onWaiting;

        final result = s.data;
        switch (result?.type) {
          case ModIconResultType.found:
            return Image.memory(
              result!.bytes!,
              height: widget.size,
              width: widget.size,
              // 列表滚动时同一位置的 element 会复用，避免闪现上一张的图
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => onNetworkError,
            );
          case ModIconResultType.missing:
            return onMissing;
          case ModIconResultType.networkError:
          case null:
            return onNetworkError;
        }
      },
    );
  }
}
