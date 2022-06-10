import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_aliyun_oss/src/better_aliyun_oss_credentials.dart';
import 'package:better_aliyun_oss/src/better_aliyun_oss_http.dart';
import 'package:better_aliyun_oss/src/better_aliyun_oss_part.dart';
import 'package:better_aliyun_oss/src/better_aliyun_oss_signer.dart';
import 'package:better_file_md5_plugin/better_file_md5_plugin.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tuple/tuple.dart';
import 'package:xml/xml.dart';

enum BetterAliyunOssClientEventEnum { progress, failure, success }

/// 阿里上传过程中的事件
class BetterAliyunOssClientEvent {
  final int requestTaskId;
  final BetterAliyunOssClientEventEnum event;
  dynamic data;

  BetterAliyunOssClientEvent(this.requestTaskId, this.event, {this.data});

  @override
  String toString() {
    return 'BetterAliyunOssClientEvent{requestTaskId: $requestTaskId, event: $event, data: $data}';
  }
}

/// 阿里上传过程中的错误
class BetterAliyunOssClientException implements Exception {
  final String message;

  BetterAliyunOssClientException({required this.message});

  @override
  String toString() {
    return 'BetterAliyunOssClientException{message: $message}';
  }
}

/// 阿里云上传请求，取消上传是需要用到
class BetterAliyunOssClientRequest {
  final int requestTaskId;
  final CancelToken? cancelToken;

  BetterAliyunOssClientRequest({required this.requestTaskId, this.cancelToken});

  @override
  String toString() {
    return 'BetterAliyunOssClientRequest{requestTaskId: $requestTaskId, cancelToken: $cancelToken}';
  }
}

/// 阿里云上传
class BetterAliyunOssClient {
  // 生成http请求签名
  BetterAliyunOssSigner? _signer;

  // 打开日志
  final bool enableLog;

  // 阿里云鉴权
  final Future<BetterAliyunOssCredentials?> Function() credentials;

  // 每个请求都会有一个Key
  static int _requestKey = 1;

  // 每个请求都会有一个监听
  Map<int, StreamSubscription> _requestSubscriptionMap = {};

  // 阿里上传过程中的事件分发
  StreamController<BetterAliyunOssClientEvent> _controller = StreamController.broadcast();

  Stream<BetterAliyunOssClientEvent> get eventStream => _controller.stream;

  BetterAliyunOssClient(this.credentials, {this.enableLog = true});

  dispose() {
    _controller.close();
  }

  /// 上传数据
  ///
  /// bucket: 阿里云Bucket，鉴权后获取相应的值
  /// endpoint: 阿里云Endpoint，鉴权后获取相应的值
  /// domain: Oss服务器绑定的域名，鉴权后获取相应的值。如果不填写默认为 https://$bucket.$endpoint
  /// objectPath: 阿里云服务器文件路径
  /// path: 待上传的文件路径: 比如相册中的图片
  /// buffer: 待上传的数据: 比如动态生成的图片
  /// contentType: 文件类型. 常见的有: image/png image/jpeg audio/mp3 video/mp4 阿里云支持的上传文件类型 https://help.aliyun.com/document_detail/39522.html
  ///
  /// return: 阿里上传请求，取消上传 和 监听上传事件时需要用到
  ///
  BetterAliyunOssClientRequest putObject({
    required AsyncValueGetter<String> bucket,
    required AsyncValueGetter<String> endpoint,
    AsyncValueGetter<String>? domain,
    required String objectPath,
    String? path,
    Uint8List? buffer,
    required String contentType,
  }) {
    // 生成请求标识
    final requestTaskId = _requestKey++;
    final cancelToken = CancelToken();

    final handle = () async* {
      // 判断文件或者数据是否存在
      if (path == null && buffer == null) {
        final exception = BetterAliyunOssClientException(message: "阿里云Oss无法找到待上传的内容");
        _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
        return;
      }

      // 开始上传
      try {
        String contentMD5 = "";
        int contentLength = 0;
        dynamic data;

        // 获取文件内容
        if (path != null) {
          final file = File(path);
          final exists = await file.exists();
          yield 0;

          if (exists == false) {
            final exception = BetterAliyunOssClientException(message: "阿里云Oss无法找到待上传的内容");
            _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
            return;
          }

          final fileMD5 = await BetterFileMd5.md5(path);
          yield 0;

          if (fileMD5 == null) {
            final exception = BetterAliyunOssClientException(message: "阿里云Oss无法解析文件");
            _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
            return;
          }

          final fileLength = await file.length();
          yield 0;

          if (fileLength <= 0) {
            final exception = BetterAliyunOssClientException(message: "阿里云Oss无法解析文件");
            _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
            return;
          }

          contentMD5 = fileMD5;
          contentLength = fileLength;
          data = File(path).openRead();
        } else if (buffer != null) {
          // 获取buffer内容
          if (buffer.length <= 0) {
            final exception = BetterAliyunOssClientException(message: "阿里云Oss无法解析文件");
            _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
            return;
          }

          contentMD5 = base64Encode(md5.convert(buffer).bytes);
          contentLength = buffer.length;

          data = Stream.fromIterable(buffer.map((e) => [e]));
        }

        // 获取Oss签名
        final verifyCredentialsResult = await verifyCredentials();
        yield 0;

        if (!verifyCredentialsResult) {
          final exception = BetterAliyunOssClientException(message: "阿里云Oss签名失败");
          _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
          return;
        }

        String bucketValue = await bucket();
        String endpointValue = await endpoint();
        String domainValue;

        if (domain == null) {
          domainValue = "https://$bucketValue.$endpointValue";
        } else {
          domainValue = await domain();
        }

        // 上传的到阿里云的地址
        final String requestUrl = 'https://$bucketValue.$endpointValue/$objectPath';

        // 访问数据时的域名地址
        final String finallyUrl = '$domainValue/$objectPath';

        // 请求时间
        final date = _requestTime();

        // 请求头
        Map<String, String> headers = {
          'Content-Type': contentType,
          'Content-Length': contentLength.toString(),
          'Content-MD5': contentMD5,
          'Date': date,
          'Host': "$bucketValue.$endpointValue",
          "x-oss-security-token": _signer!.credentials.securityToken,
        };

        // 计算签名
        final authorization = _signer!.sign(
          httpMethod: 'PUT',
          bucketName: bucketValue,
          objectName: objectPath,
          headers: headers,
        );
        headers["Authorization"] = authorization;

        // 开始上传
        await BetterAliyunOssDioUtils.getInstance(enableLog).put<void>(
          requestUrl,
          data: data,
          options: Options(headers: headers, responseType: ResponseType.plain),
          cancelToken: cancelToken,
          onSendProgress: (int count, int total) {
            // 上传进度
            _controller.sink
                .add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.progress, data: {"count": count, "total": total}));
          },
        );
        yield 0;

        // 上传成功
        _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.success, data: finallyUrl));
      } catch (e) {
        // 上传失败
        final exception = BetterAliyunOssClientException(message: "上传失败");
        _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
      }
    };

    _requestSubscriptionMap[requestTaskId] = handle().listen((event) {}, onDone: () => _requestSubscriptionMap.remove(requestTaskId));
    return BetterAliyunOssClientRequest(requestTaskId: requestTaskId, cancelToken: cancelToken);
  }

  /// 文件分片上传第一步：初始化一个分片上传事件
  ///
  /// bucket: 阿里云Bucket，鉴权后获取相应的值
  /// endpoint: 阿里云Endpoint，鉴权后获取相应的值
  /// domain: Oss服务器绑定的域名，鉴权后获取相应的值。如果不填写默认为 https://$bucket.$endpoint
  /// objectPath: 阿里云服务器文件路径
  /// path: 待上传的文件路径: 比如相册中的图片
  /// contentType: 文件类型. 常见的有: image/png image/jpeg audio/mp3 video/mp4 阿里云支持的上传文件类型 https://help.aliyun.com/document_detail/39522.html
  ///
  /// return: 文件分片列表
  ///
  Future<Tuple2<List<BetterAliyunOssPart>?, BetterAliyunOssClientException?>> initiateMultipartUpload({
    required AsyncValueGetter<String> bucket,
    required AsyncValueGetter<String> endpoint,
    AsyncValueGetter<String>? domain,
    required String objectPath,
    required String filePath,
    required String contentType,
  }) async {
    try {
      // 获取文件内容
      final file = File(filePath);
      final exists = await file.exists();

      if (exists == false) {
        final exception = BetterAliyunOssClientException(message: "阿里云Oss无法找到待上传的内容");
        return Tuple2(null, exception);
      }

      final fileMD5 = await BetterFileMd5.md5(filePath);
      if (fileMD5 == null) {
        final exception = BetterAliyunOssClientException(message: "阿里云Oss无法解析文件");
        return Tuple2(null, exception);
      }

      final fileLength = file.lengthSync();
      if (fileLength <= 0) {
        final exception = BetterAliyunOssClientException(message: "阿里云Oss无法解析文件");
        return Tuple2(null, exception);
      }

      // 获取Oss签名
      final verifyCredentialsResult = await verifyCredentials();
      if (!verifyCredentialsResult) {
        final exception = BetterAliyunOssClientException(message: "阿里云Oss签名失败");
        return Tuple2(null, exception);
      }

      String bucketValue = await bucket();
      String endpointValue = await endpoint();
      String domainValue;

      if (domain == null) {
        domainValue = "https://$bucketValue.$endpointValue";
      } else {
        domainValue = await domain();
      }

      Stream<List<int>> data = File(filePath).openRead();

      // 上传的到阿里云的地址
      final String requestUrl = 'https://$bucketValue.$endpointValue/$objectPath?uploads';

      // 请求时间
      final date = _requestTime();

      // 请求头
      Map<String, String> headers = {
        'Content-Type': contentType,
        'Date': date,
        'Host': "$bucketValue.$endpointValue",
        "x-oss-security-token": _signer!.credentials.securityToken,
      };

      // 计算签名
      final authorization = _signer!.sign(
        httpMethod: 'POST',
        bucketName: bucketValue,
        objectName: "$objectPath?uploads",
        headers: headers,
      );
      headers["Authorization"] = authorization;

      // 提交请求
      final result = await BetterAliyunOssDioUtils.getInstance(enableLog).post<String>(
        requestUrl,
        data: data,
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
      final xml = XmlDocument.parse(result.data ?? "");
      final uploadIdList = xml.findAllElements("UploadId");
      if (uploadIdList.length == 0) {
        final exception = BetterAliyunOssClientException(message: "上传失败");
        return Tuple2(null, exception);
      }
      String uploadId = uploadIdList.first.text;

      // 计算分片
      List<BetterAliyunOssPart> ossPartList = [];
      int partLength = _calculatePartLength(fileLength);
      for (int i = 0; i < (fileLength ~/ partLength) + 1; i++) {
        final partRangeStart = i * partLength;
        if (partRangeStart < fileLength) {
          final ossPart = BetterAliyunOssPart.init(
            bucket: bucketValue,
            endpoint: endpointValue,
            domain: domainValue,
            objectPath: objectPath,
            filePath: filePath,
            uploadId: uploadId,
            partNumber: i + 1,
            partRangeStart: partRangeStart,
            partRangeLength: partRangeStart + partLength <= fileLength ? partLength : fileLength - partRangeStart,
          );
          ossPartList.add(ossPart);
        }
      }

      return Tuple2(ossPartList, null);
    } catch (e) {
      final exception = BetterAliyunOssClientException(message: "上传失败");
      return Tuple2(null, exception);
    }
  }

  /// 文件分片上传第二步：分片上传数据
  ///
  /// part: 分片数据
  ///
  /// return: 阿里上传请求，取消上传 和 监听上传事件时需要用到
  ///
  BetterAliyunOssClientRequest uploadPart({required BetterAliyunOssPart part}) {
    // 生成请求标识
    final requestTaskId = _requestKey++;
    final cancelToken = CancelToken();

    final handle = () async* {
      // 开始上传
      try {
        // 获取文件内容
        final file = File(part.filePath);
        final exists = await file.exists();
        yield 0;

        if (exists == false) {
          final exception = BetterAliyunOssClientException(message: "阿里云Oss无法找到待上传的内容");
          _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
          return;
        }

        // 获取Oss签名
        final verifyCredentialsResult = await verifyCredentials();
        yield 0;

        if (!verifyCredentialsResult) {
          final exception = BetterAliyunOssClientException(message: "阿里云Oss签名失败");
          _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
          return;
        }

        dynamic data = File(part.filePath).openRead(part.partRangeStart, part.partRangeStart + part.partRangeLength);

        // 上传的到阿里云的地址
        final String requestParams = "partNumber=${part.partNumber}&uploadId=${part.uploadId}";
        final String requestUrl = 'https://${part.bucket}.${part.endpoint}/${part.objectPath}?$requestParams';

        // 请求时间
        final date = _requestTime();

        // 请求头
        Map<String, String> headers = {
          'Content-Length': part.partRangeLength.toString(),
          'Content-Type': 'application/octet-stream',
          'Date': date,
          'Host': "${part.bucket}.${part.endpoint}",
          "x-oss-security-token": _signer!.credentials.securityToken,
        };

        // 计算签名
        final authorization = _signer!.sign(
          httpMethod: 'PUT',
          bucketName: part.bucket,
          objectName: "${part.objectPath}?$requestParams",
          headers: headers,
        );
        headers["Authorization"] = authorization;

        // 开始上传
        final result = await BetterAliyunOssDioUtils.getInstance(enableLog).put<String>(
          requestUrl,
          data: data,
          options: Options(headers: headers, responseType: ResponseType.plain),
          cancelToken: cancelToken,
          onSendProgress: (int count, int total) {
            // 上传进度
            if (count % 1024 == 0 || count == total)
              _controller.sink
                  .add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.progress, data: {"count": count, "total": total}));
          },
        );
        yield 0;

        final eTag = result.headers.map['ETag'];
        if (eTag != null && eTag.length > 0) {
          // 上传成功
          _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.success, data: eTag.first.toString()));
        } else {
          // 上传失败
          final exception = BetterAliyunOssClientException(message: "上传失败");
          _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
        }
      } catch (e) {
        // 上传失败
        final exception = BetterAliyunOssClientException(message: "上传失败");
        _controller.sink.add(BetterAliyunOssClientEvent(requestTaskId, BetterAliyunOssClientEventEnum.failure, data: exception));
      }
    };

    _requestSubscriptionMap[requestTaskId] = handle().listen((event) {}, onDone: () => _requestSubscriptionMap.remove(requestTaskId));
    return BetterAliyunOssClientRequest(requestTaskId: requestTaskId, cancelToken: cancelToken);
  }

  /// 文件分片上传第三步：完成整个文件的分片上传
  ///
  /// partList: 分片数据
  ///
  /// return: 返回最终的URL
  Future<Tuple2<String?, BetterAliyunOssClientException?>> completeMultipartUpload({required List<BetterAliyunOssPart> partList}) async {
    // 获取Oss签名
    final verifyCredentialsResult = await verifyCredentials();
    if (!verifyCredentialsResult) {
      final exception = BetterAliyunOssClientException(message: "阿里云Oss签名失败");
      return Tuple2(null, exception);
    }

    try {
      final sb = StringBuffer();
      sb.write('<CompleteMultipartUpload>');
      for (final part in partList) {
        sb.write("<Part>");
        sb.write("<PartNumber>${part.partNumber}</PartNumber>");
        sb.write("<ETag>${part.partETag}</ETag>");
        sb.write("</Part>");
      }
      sb.write('</CompleteMultipartUpload>');
      final xml = XmlDocument.parse(sb.toString()).toXmlString(pretty: true);

      final rawData = Uint8List.fromList(utf8.encode(xml));
      final data = Stream.fromIterable(Uint8List.fromList(utf8.encode(xml)).map((e) => [e]));

      // 上传到阿里云的地址
      final String requestUrl = 'https://${partList[0].bucket}.${partList[0].endpoint}/${partList[0].objectPath}?uploadId=${partList[0].uploadId}';

      String contentMD5 = base64Encode(md5.convert(rawData).bytes);

      // 请求时间
      final date = _requestTime();

      // 请求头
      Map<String, String> headers = {
        'content-length': rawData.length.toString(),
        'content-type': 'application/xml',
        'content-md5': contentMD5,
        'Date': date,
        'Host': "${partList[0].bucket}.${partList[0].endpoint}",
        "x-oss-security-token": _signer!.credentials.securityToken,
      };

      // 计算签名
      final authorization = _signer!.sign(
        httpMethod: 'POST',
        bucketName: partList[0].bucket,
        objectName: "${partList[0].objectPath}?uploadId=${partList[0].uploadId}",
        headers: headers,
      );
      headers["Authorization"] = authorization;

      // 提交请求
      await BetterAliyunOssDioUtils.getInstance(enableLog).post<void>(
        requestUrl,
        data: data,
        options: Options(headers: headers, responseType: ResponseType.plain),
      );

      String domain;
      if (partList[0].domain != null) {
        domain = partList[0].domain!;
      } else {
        domain = "https://${partList[0].bucket}.${partList[0].endpoint}";
      }

      // 访问数据时的域名地址
      return Tuple2('$domain/${partList[0].objectPath}', null);
    } catch (e) {
      final exception = BetterAliyunOssClientException(message: "上传失败 $e");
      return Tuple2(null, exception);
    }
  }

  /// 取消上传数据
  ///
  /// request: 请求上传接口的返回值
  ///
  Future cancelPutObject(BetterAliyunOssClientRequest request) async {
    final requestSubscription = _requestSubscriptionMap[request.requestTaskId];
    if (requestSubscription != null) {
      // 结束上传流程
      await requestSubscription.cancel();
      // 结束Dio上传
      request.cancelToken?.cancel();
      _requestSubscriptionMap.remove(request.requestTaskId);
    }
  }
}

extension _Utils on BetterAliyunOssClient {
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

  int _calculatePartLength(int length) {
    if (length / 1024 / 1024 < 1000) {
      return 1024 * 1024;
    } else {
      return length ~/ 999;
    }
  }
}
