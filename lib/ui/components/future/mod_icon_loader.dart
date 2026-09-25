import 'dart:typed_data';

import 'package:copper_launcher/data/models.dart';
import 'package:copper_launcher/ui/vars.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:flutter/material.dart';

/// 图标探测结果：把「确认没有图标」和「网络失败」分开。
///
/// 两者在 UI 上要给不同的占位，且**网络失败不能写入缺失缓存**——
/// 否则一次网络抖动会把图标永久判定为缺失（直到重启）。
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
  final ModOfficialListMeta modMeta;
  final double size;

  /// 探测中占位（默认转圈）
  final Widget? onWaiting;

  /// 该模组确实没有图标（候选地址全不存在）时的占位
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
  /// 探测候选：分支 × 路径 × 后缀，命中第一个就停
  static const _branchCandidates = ['main', 'master'];
  static const _pathCandidates = ['icon', 'assets/icon'];
  static const _formatCandidates = ['png', 'jpg', 'jpeg'];

  /// 探测并加载图标的 Future，只建一次
  late Future<ModIconResult> _iconFuture;

  @override
  void initState() {
    super.initState();
    _iconFuture = _loadIcon();
  }

  @override
  void didUpdateWidget(covariant ModNetworkIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 翻页 / 改筛选时同一位置的 element 会换到另一个 mod，得重新探测
    if (oldWidget.modMeta != widget.modMeta) {
      _iconFuture = _loadIcon();
    }
  }

  /// 候选图标地址（分支 × 路径 × 后缀）
  Iterable<({String url, String branch})> _candidateUrls(String repoUrl) sync* {
    for (final format in _formatCandidates) {
      for (final branch in _branchCandidates) {
        for (final path in _pathCandidates) {
          yield (url: '$repoUrl/$branch/$path.$format', branch: branch);
        }
      }
    }
  }

  /// 先探测地址（HEAD），再走 cio 拉字节——两步都成，才算 found
  Future<ModIconResult> _loadIcon() async {
    final probe = await _probeIcon();
    if (probe.type != ModIconResultType.found) return probe;

    final bytes = await _fetchBytes(probe.url!);
    if (bytes == null) return const ModIconResult.networkError();
    return ModIconResult.found(probe.url!, bytes);
  }

  /// 拉图标字节：**必须走 cio**（代理 / 镜像可达）。
  ///
  /// raw.githubusercontent.com 在部分网络（如广电）下直连不通，`Image.network`
  /// 会直接失败——所以这里拿字节交给 `Image.memory`，与 README 图片同一套做法
  Future<Uint8List?> _fetchBytes(String url) async {
    try {
      final res = await cio.get<Uint8List>(
        url,
        headers: modDownloadHeaders,
        responseType: ResponseType.bytes,
      );
      final data = res.data;
      if (res.statusCode != 200 || data == null || data.isEmpty) {
        addLog(.warning, '贴图响应异常（HTTP ${res.statusCode}）：$url', tag: 'ModIcon');
        return null;
      }
      return data;
    } on DioException catch (e) {
      addLog(
        .warning,
        '贴图加载失败：$url（${e.type.name}：${removeNewlines(e.message ?? '')}）',
        tag: 'ModIcon',
      );
      return null;
    } catch (e) {
      addLog(.warning, '贴图加载失败：$url（${removeNewlines('$e')}）', tag: 'ModIcon');
      return null;
    }
  }

  Future<ModIconResult> _probeIcon() async {
    final meta = widget.modMeta;

    if (meta.iconUrlCache != null) return ModIconResult.found(meta.iconUrlCache!);
    // 探过且确认没有图标：直接返回，别再跑一轮
    if (meta.iconMissingCache) return const ModIconResult.missing();

    final repoUrl = 'https://raw.githubusercontent.com/${meta.repo}';
    addLog(.debug, '探测图标：${meta.repo}', tag: 'ModIcon');
    for (final candidate in _candidateUrls(repoUrl)) {
      try {
        final res = await cio.head(candidate.url, headers: modDownloadHeaders);
        if (res.statusCode == 200 || res.data != null) {
          meta.iconUrlCache = candidate.url;
          meta.mainBranchCache = candidate.branch;
          addLog(
            .debug,
            '命中：${meta.repo} → ${candidate.url}',
            tag: 'ModIcon',
          );
          return ModIconResult.found(candidate.url);
        }
      } on DioException catch (e) {
        // 网络类失败：不是「没有图标」，立即中止探测且**不写缺失缓存**
        if (isNetworkFailure(e)) {
          addLog(
            .warning,
            '探测网络失败：${meta.repo} @ ${candidate.url}'
            '（${e.type.name}：${removeNewlines(e.message ?? '')}）',
            tag: 'ModIcon',
          );
          return const ModIconResult.networkError();
        }
        // 404 等：该候选不存在，换下一个
      } catch (_) {
        // 其它异常同样按候选不存在处理
      }
    }

    meta.iconMissingCache = true;
    addLog(.debug, '图标缺失：${meta.repo}（候选地址全部不存在）', tag: 'ModIcon');
    return const ModIconResult.missing();
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
