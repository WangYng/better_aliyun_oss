import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:better_aliyun_oss/better_aliyun_oss.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late BetterAliyunOssClient ossClient;

  late StreamSubscription eventStreamSubscription;

  // 简单数据上传请求
  BetterAliyunOssClientRequest? simplePutRequest;

  // 分片数据
  List<BetterAliyunOssPart> partList = [];

  // 分片数据上传请求
  Map<BetterAliyunOssPart, BetterAliyunOssClientRequest> partRequestMap = {};

  @override
  void initState() {
    super.initState();

    ossClient = BetterAliyunOssClient(credentials);
    eventStreamSubscription = ossClient.eventStream.listen((event) {
      if (event.event == BetterAliyunOssClientEventEnum.progress) {
        return;
      }

      print("$event");

      for (final part in partList) {
        if (partRequestMap[part]!.requestTaskId == event.requestTaskId && event.event == BetterAliyunOssClientEventEnum.success) {
          part.partETag = event.data.toString();
        }
      }
    });
  }

  @override
  void dispose() {
    eventStreamSubscription.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                child: Text('基础上传'),
                onPressed: simpleUpload,
              ),
              CupertinoButton(
                child: Text('取消基础上传'),
                onPressed: cancelSimpleUpload,
              ),
              CupertinoButton(
                child: Text('分片上传 初始化'),
                onPressed: initiateMultipartUpload,
              ),
              CupertinoButton(
                child: Text('分片上传'),
                onPressed: uploadPartList,
              ),
              CupertinoButton(
                child: Text('取消分片上传'),
                onPressed: cancelUploadPartList,
              ),
              CupertinoButton(
                child: Text('分片上传 完成'),
                onPressed: completeMultipartUpload,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void simpleUpload() async {
    // 保存图片到本地
    final bytes = Uint8List.view((await rootBundle.load("images/landscape.jpeg")).buffer);
    final file = File(path.join((await getTemporaryDirectory()).path, "landscape.jpeg"));
    if (!file.existsSync()) {
      await file.writeAsBytes(bytes);
    }

    final objectFileName = Uuid().v1().replaceAll("-", "") + path.extension(file.path);
    final objectPath = "image/diary/${DateFormat("yyyyMM").format(DateTime.now())}/$objectFileName";

    simplePutRequest = ossClient.putObject(
      bucket: "my-bucket",
      endpoint: "oss-cn-hangzhou.aliyuncs.com",
      domain: "https://domain.com",
      objectPath: objectPath,
      contentType: lookupMimeType(file.path) ?? "application/octet-stream",
      buffer: bytes,
    );

    print("简单数据上传请求 id : ${simplePutRequest!.requestTaskId}");
  }

  void cancelSimpleUpload() {
    if (simplePutRequest != null) {
      ossClient.cancelPutObject(simplePutRequest!);
    }
  }

  void initiateMultipartUpload() async {
    // 保存图片到本地
    final bytes = Uint8List.view((await rootBundle.load("images/landscape.jpeg")).buffer);
    final file = File(path.join((await getTemporaryDirectory()).path, "landscape.jpeg"));
    if (!file.existsSync()) {
      await file.writeAsBytes(bytes);
    }

    final objectFileName = Uuid().v1().replaceAll("-", "") + path.extension(file.path);
    final objectPath = "image/diary/${DateFormat("yyyyMM").format(DateTime.now())}/$objectFileName";

    final partListTuple = await ossClient.initiateMultipartUpload(
      bucket: "my-bucket",
      endpoint: "oss-cn-hangzhou.aliyuncs.com",
      domain: "https://domain.com",
      objectPath: objectPath,
      contentType: lookupMimeType(file.path) ?? "application/octet-stream",
      filePath: file.path,
    );

    if (partListTuple.item1 != null) {
      partList = partListTuple.item1!;
      print("数据分片成功 $partList");
    } else {
      print("数据分片失败 ${partListTuple.item2}");
    }
  }

  void uploadPartList() async {
    for (var part in partList) {
      final request = ossClient.uploadPart(part: part);
      partRequestMap[part] = request;

      print("数据分片 ${part.partNumber} 的上传请求 id : ${request.requestTaskId}");
    }
  }

  void cancelUploadPartList() {
    if (partRequestMap.keys.length > 0) {
      for (final request in partRequestMap.values.toList()) {
        ossClient.cancelPutObject(request);
      }
      partRequestMap.clear();
    }
  }

  void completeMultipartUpload() async {
    final result = await ossClient.completeMultipartUpload(partList: partList);

    if (result.item1 != null) {
      print("数据分片上传成功 ${result.item1}");
    } else {
      print("数据分片上传失败 ${result.item2}");
    }
  }

  Future<BetterAliyunOssCredentials?> credentials() async {
    final credentials = {
      "SecurityToken": "",
      "AccessKeyId": "",
      "AccessKeySecret": "",
      "Expiration": "",
    };
    return BetterAliyunOssCredentials.fromMap(credentials);
  }
}
