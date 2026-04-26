import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path/path.dart' as p;

import 'math/speed_calculate.dart';

final dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 20), //链接超时
    receiveTimeout: const Duration(seconds: 300), //下载超时
  ),
);

typedef SpeedUpdateCallback = void Function(double);
typedef DownloadStatusCallback = void Function(String);
typedef DownloadEndCallback = void Function(List<String>);

class Downloader {
  int maxTryTime = 5;

  //尝试编辑一个序列，下载分块会进入序列中，尝试第一次链接。链接失败的分块，再次进入序列，之后重复链接，待所有的分块都能正确连接后再开始下载
  //todo 动态调整分块，若出现部分分块下载速度较快，部分分块下载较慢，会尝试将较慢分块继续拆分为更小的分块继续下载，之前已经下载的部分，会在到达下一部分时停止下载
  Future<void> download(
    String url,
    String savePath, {
    String? tempPath,
    int chunkNum = 8,
    ProgressCallback? onProgress,
    SpeedUpdateCallback? onSpeedUpdate,
    //DownloadEndCallback? onEnd,
    //Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    //String lengthHeader = Headers.contentLengthHeader,
    //Object? data,
    Options? options,
  }) async {
    final Response headResp = await dio.head(url);
    final int totalSize = int.parse(headResp.headers.value('content-length')!);

    final chunkSize = totalSize ~/ chunkNum;

    tempPath ??= '$savePath.temp.';

    final List<DownloadChunk> chunks = [];
    for (int i = 0; i < chunkNum; i++) {
      final start = i * chunkSize;
      final int end;
      if (i != chunkNum - 1) {
        end = (i + 1) * chunkSize - 1;
      } else {
        end = totalSize;
      }
      final path = '$tempPath$i';
      final file = File(path);
      var receive = 0;
      if (await file.exists()) {
        receive = await file.length();
        if (receive > end - start) {
          await file.delete();
          receive = 0;
        }
      }
      final chunk = DownloadChunk(i, start + receive, end, path)
        ..receive = receive;
      chunks.add(chunk);
    }

    Future<bool> checkConnection(DownloadChunk chunk, {int tryTime = 0}) async {
      chunk.status = DownloadChunkStatus.connection;
      try {
        final res = await dio.head(
          url,
          options: Options(
            headers: {'Range': 'bytes=${chunk.start}-${chunk.end}'},
          ),
        );
        if (res.statusCode == 206) {
          return true;
        } else {
          throw DioException(requestOptions: RequestOptions());
        }
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        if (tryTime < maxTryTime) {
          await Future.delayed(Duration(milliseconds: 500));
          tryTime++;
          return await checkConnection(chunk, tryTime: tryTime);
        } else {
          return false;
        }
      }
    }

    final connectionStatus = await Future.wait(
      chunks.map((it) async => await checkConnection(it)),
    );
    final allReady = connectionStatus.every((ok) => ok);
    if (!allReady) {
      throw Exception('链接服务器时出现问题');
    }

    ValueNotifier<int>? sizeNotifier;
    SpeedCalculator? speedCalculator;
    if (onSpeedUpdate != null) {
      sizeNotifier = ValueNotifier<int>(0);
      speedCalculator = SpeedCalculator(
        dataNotifier: sizeNotifier,
        updateCallback: onSpeedUpdate,
      );
    }
    Future<void> downloadSingleChunk(DownloadChunk chunk, {tryTime = 0}) async {
      // late final Options op;
      // if (options == null) {
      //   op = Options(headers: {'Range': 'bytes=${it.start}-${it.end}'});
      // } else {
      //   if (options.headers != null) {
      //     op = options.copyWith(
      //       headers:
      //       options.headers!
      //         ..addAll({'Range': 'bytes=${it.start}-${it.end}'}),
      //     );
      //   } else {
      //     op = options.copyWith(
      //       headers: {'Range': 'bytes=${it.start}-${it.end}'},
      //     );
      //   }
      // }
      chunk.status == DownloadChunkStatus.download;
      final recentReceive = chunk.receive;
      try {
        await dio.download(
          url,
          chunk.path,
          cancelToken: cancelToken,
          deleteOnError: deleteOnError,
          fileAccessMode: fileAccessMode,
          options: Options(
            headers: {'Range': 'bytes=${chunk.start}-${chunk.end}'},
          ),
          onReceiveProgress: (receive, r) {
            chunk.receive = receive + recentReceive;
            final currentReceive = chunks.fold<int>(
              0,
              (l, it) => l + it.receive,
            );
            sizeNotifier?.value = currentReceive;
            onProgress?.call(currentReceive, totalSize);
          },
        );
        chunk.status = DownloadChunkStatus.finished;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        await Future.delayed(Duration(milliseconds: 500));
        if (tryTime < maxTryTime) {
          tryTime++;
          await downloadSingleChunk(chunk, tryTime: tryTime);
        }else{
          chunk.status = DownloadChunkStatus.failed;
          throw Exception('分块[${chunk.index}下载尝试次数过多]');
        }
      }
    }

    try {
      await Future.wait(
        chunks.map((it) async => await downloadSingleChunk(it)),
        eagerError: true,
      );
      final file = File(savePath);
      //if (await file.exists()) file.delete();
      final IOSink mainSink = file.openWrite();
      for (final it in chunks) {
        final File tempFile = File(it.path);
        await mainSink.addStream(tempFile.openRead());
        await tempFile.delete(); // 删除临时分块文件
      }
      await mainSink.close();
    } on DioException catch (e) {
      if (deleteOnError) {
        for (var it in chunks) {
          await File(it.path).delete();
        }
      }
      rethrow;
    } finally {
      speedCalculator?.cancel();
    }
  }
}

class DownloadChunk {
  DownloadChunk(
    this.index,
    this.start,
    this.end,
    this.path, {
    this.status = DownloadChunkStatus.pending,
  });
  final int index;
  final int start;
  final int end;
  int receive = 0;
  final String path;
  // late final String cdnUrl;
  DownloadChunkStatus status;
}

enum DownloadChunkStatus { pending, connection, download, finished, failed }
