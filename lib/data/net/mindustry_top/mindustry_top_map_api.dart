import 'dart:convert';

import 'package:copper_launcher/core/app_constant.dart';
import 'package:copper_launcher/data/net/mindustry_top/mindustry_top_map_meta.dart';
import 'package:copper_launcher/util/io/copper_io.dart';
import 'package:copper_launcher/util/io/log.dart';
import 'package:copper_launcher/util/format/string_cleaner.dart';

/// mindustry.top 资源站的地图接口封装（站点拥有者公开的接口）。
///
/// - 列表按 offset 翻页，每页 15 条，越界返回 400 → 本封装折算为空列表
/// - 请求走统一网络入口 [cio]（自带代理跟随），不经 github 镜像回退
///   （非 github 域名，镜像逻辑自动跳过）
class MindustryTopMapApi {
  /// 每页条数（服务端固定 15，用于翻页判断是否到末尾）
  static const pageSize = 15;

  /// 拉取地图列表。
  ///
  /// [begin] 为条目偏移（非页码），[search] 关键词匹配站内地图名与简介，
  /// 传空表示不筛选。
  ///
  /// begin 越过末尾时站点返回 400，视为空列表（翻页终止条件）；
  /// 其余网络错误原样抛出，由调用方决定提示方式
  static Future<List<MindustryTopMapMeta>> list({
    int begin = 0,
    String? search,
    CancelToken? cancelToken,
  }) async {
    final queryParameters = {
      'begin': '$begin',
      if (search != null && search.isNotEmpty) 'search': search,
    };
    try {
      final res = await cio.get<String>(
        '$mindustryTopApiBase/maps/list',
        queryParameters: queryParameters,
        responseType: ResponseType.plain,
        cancelToken: cancelToken,
      );
      return parseMapMetaList(res.data ?? '');
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) return const [];
      rethrow;
    }
  }

  /// 拉取地图详情
  static Future<MindustryTopMapDetail> detail(
    int id, {
    CancelToken? cancelToken,
  }) async {
    final res = await cio.get<String>(
      '$mindustryTopApiBase/maps/$id.json',
      responseType: ResponseType.plain,
      cancelToken: cancelToken,
    );
    final decoded = jsonDecode(res.data ?? '');
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('地图详情响应不是 JSON 对象：$id');
    }
    return MindustryTopMapDetail.fromJson(decoded);
  }

  /// 下载地图本体（`.msav`，zlib 压缩的地图文件，落盘后游戏可直接识别）。
  ///
  /// 下载进度经 [onStatus] 回调（复用 cio 的分块 / 单流统一管线），
  /// [savePath] 一般取目标版本的 `mapsPath/<地图名>.msav`
  static Future<void> download({
    required int id,
    required String savePath,
    CancelToken? cancelToken,
    HttpStatusCallback? onStatus,
  }) async {
    await cio.download(
      url: '$mindustryTopApiBase/maps/$id.msav',
      savePath: savePath,
      cancelToken: cancelToken,
      onStatus: onStatus,
    );
  }

  /// 下载失败时记一条运行日志（网络问题与站点 4xx/5xx 分开描述）
  static void logFailure(Object error, {String? context}) {
    final statusText = error is DioException
        ? '（HTTP ${error.response?.statusCode ?? '无响应'}）'
        : '';
    addLogAndPrint(
      .error,
      'mindustry.top 地图${context ?? '请求'}失败$statusText：${removeNewlines('$error')}',
      tag: 'MapDownload',
    );
  }
}
