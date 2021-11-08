import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_aliyun_oss/src/better_aliyun_oss_credentials.dart';
import 'package:better_aliyun_oss/src/better_aliyun_oss_http.dart';
import 'package:better_aliyun_oss/src/better_aliyun_oss_signer.dart';
import 'package:better_file_md5_plugin/better_file_md5_plugin.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

enum BetterAliyunOssClientEventEnum { progress, failure, success }

/// 阿里上传过程中的事件
class BetterAliyunOssClientEvent {
  final int requestToaskId;
  final BetterAliyunOssClientEventEnum event;
  dynamic data;

  BetterAliyunOssClientEvent(this.requestToaskId, this.event, {this.data});

  @override
  String toString() {
    return 'BetterAliyunOssClientEvent{requestToaskId: $requestToaskId, event: $event, data: $data}';
  }
}

/// 阿里云上传
class BetterAliyunOssClient {
  // 生成http请求签名
  BetterAliyunOssSigner? _signer;

  // 阿里云鉴权
  final Future<BetterAliyunOssCredentials?> Function() credentials;

  // 每个请求都会有一个Key
  static int _requestKey = 1;

  // 阿里上传过程中的事件分发
  StreamController<BetterAliyunOssClientEvent> _controller = StreamController.broadcast();

  Stream<BetterAliyunOssClientEvent> get eventStream => _controller.stream;

  BetterAliyunOssClient(this.credentials);

  dispose() {
    _controller.close();
  }

  /// 上传数据
  ///
  /// bucket: 阿里云Bucket
  /// endpoint: 阿里云Endpoint
  /// domain: Oss服务器绑定的域名. 如果不填写默认为 https://$bucket.$endpoint
  /// objectPath: 阿里云服务器文件路径
  /// path: 待上传的文件路径: 比如相册中的图片
  /// buffer: 待上传的数据: 比如动态生成的图片
  /// contentType: 文件类型. 常见的有: image/png image/jpeg audio/mp3 video/mp4 阿里云支持的上传文件类型 https://help.aliyun.com/document_detail/39522.html
  /// cancelToken: Dio 取消上传的句柄
  int putObject({
    required String bucket,
    required String endpoint,
    String? domain,
    required String objectPath,
    String? path,
    Uint8List? buffer,
    required String contentType,
    CancelToken? cancelToken,
  }) {
    // 生成请求标识
    final int requestToaskId = _requestKey++;

    Future.microtask(() async {
      // 判断数据
      if (path == null && buffer == null) {
        _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.failure, data: "阿里云Oss无法找到待上传的内容"));
        return;
      }

      // 获取Oss签名
      final result = await verifyCredentials();
      if (!result) {
        _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.failure, data: "阿里云Oss签名失败"));
      }

      // 开始上传
      try {
        String contentMD5 = "";
        int contentLength = 0;
        dynamic data;

        // 获取文件内容
        if (path != null) {
          final file = File(path);
          if (!(await file.exists())) {
            _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.failure, data: "阿里云Oss无法找到待上传的文件"));
            return;
          }

          final fileMD5 = await BetterFileMd5.md5(path);
          if (fileMD5 == null) {
            _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.failure, data: "阿里云Oss无法解析文件"));
            return;
          }

          final fileLength = file.lengthSync();
          if (fileLength <= 0) {
            _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.failure, data: "阿里云Oss无法解析文件"));
            return;
          }

          contentMD5 = fileMD5;
          contentLength = fileLength;
          data = File(path).readAsBytes().asStream();
          File(path).readAsBytes().asStream();
        } else if (buffer != null) {
          // 获取buffer内容
          if (buffer.length <= 0) {
            _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.failure, data: "阿里云Oss无法解析内容"));
            return;
          }

          contentMD5 = base64Encode(md5.convert(buffer).bytes);
          contentLength = buffer.length;

          data = Stream.fromIterable(buffer.map((e) => [e]));
        }

        if (domain == null) {
          domain = "https://$bucket.$endpoint";
        }

        // 上传的到阿里云的地址
        final String requestUrl = 'https://$bucket.$endpoint/$objectPath';

        // 访问数据时的域名地址
        final String finallyUrl = '$domain/$objectPath';

        // 请求时间
        final date = _requestTime();

        // 请求头
        Map<String, String> headers = {
          'Content-Type': contentType,
          'Content-Length': contentLength.toString(),
          'Content-Md5': contentMD5,
          'Date': date,
          'Host': "$bucket.$endpoint",
          "x-oss-security-token": _signer!.credentials.securityToken,
        };

        // 计算签名
        final authorization = _signer!.sign(
          httpMethod: 'PUT',
          bucketName: bucket,
          objectName: objectPath,
          headers: headers,
        );
        headers["Authorization"] = authorization;

        // 开始上传
        await BetterAliyunOssDioUtils.getInstance().put<void>(
          requestUrl,
          data: data,
          options: Options(headers: headers),
          cancelToken: cancelToken,
          onSendProgress: (int count, int total) {
            // 上传进度
            _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.progress, data: {"count": count, "total": total}));
          },
        );

        // 上传成功
        _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.success, data: finallyUrl));
      } catch (e) {
        // 上传失败
        _controller.sink.add(BetterAliyunOssClientEvent(requestToaskId, BetterAliyunOssClientEventEnum.failure, data: e.toString()));
      }
    });
    return requestToaskId;
  }

  /// 验证阿里云上传签名, 返回成功或者失败
  Future<bool> verifyCredentials() async {
    final result = await credentials.call();
    if (result != null) {
      _signer = BetterAliyunOssSigner(result);
      return true;
    }
    return false;
  }

  String _requestTime() {
    initializeDateFormatting('en', null);
    final DateTime now = DateTime.now();
    final String string = DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_ISO').format(now.toUtc());
    return '$string GMT';
  }
}
