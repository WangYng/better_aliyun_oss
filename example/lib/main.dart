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

  @override
  void initState() {
    super.initState();

    ossClient = BetterAliyunOssClient(credentials);
    eventStreamSubscription = ossClient.eventStream.listen((event) {
      print("$event");
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
          child: CupertinoButton(
            child: Text('Uploading'),
            onPressed: uploading,
          ),
        ),
      ),
    );
  }

  void uploading() async {
    // 保存图片到本地
    final bytes = Uint8List.view((await rootBundle.load("images/logo.png")).buffer);
    final file = File(path.join((await getTemporaryDirectory()).path, "logo.png"));
    if (!file.existsSync()) {
      await file.writeAsBytes(bytes);
    }

    final objectFileName = Uuid().v1().replaceAll("-", "") + path.extension(file.path);
    final objectPath = "image/diary/${DateFormat("yyyyMM").format(DateTime.now())}/$objectFileName";

    final requestTaskId = ossClient.putObject(
      bucket: "my-bucket",
      endpoint: "oss-cn-hangzhou.aliyuncs.com",
      domain: "https://mydomain.com",
      objectPath: objectPath,
      contentType: lookupMimeType(file.path) ?? "application/octet-stream",
      path: file.path,
    );

    print("requestTaskId : $requestTaskId");
  }

  Future<BetterAliyunOssCredentials?> credentials() async {
    final credentials = {
      "SecurityToken": "CAIS9AF1q6Ft5B2yfSjIr5fSGO2Mvu5M7ZKYT1HXsjcTb75vrqDEiDz2IH5Je3NsAO8at/4+nmFY6fYblrhjSpZCT03Ja40pt84JoV7/O9IoUwInS/tW5qe+EE2/VjTZvqaLEcibIfrZfvCyESOm8gZ43br9cxi7QlWhKufnoJV7b9MRLGLaBHg8c7UwHAZ5r9IAPnb8LOukNgWQ4lDdF011oAFx+wgdgOadopbEtEeD0QKk8IJP+dSteKrDRtJ3IZJyX+2y2OFLbafb2EZSkUMUqfgs0PUbpW6d74vMUwYBug/+NPHP+8VuJQRya7MhAalAoehMdVoeGoABEPahzDchG8vMhPKl63sXU79TU0PDp7o61dXBTenG8tgIbxgYox6SKoO7ETdGHNLhZY1h/e7BbrLmXmb9YnQ2UWj5VK9D0EUdlwynYz5eQe03KBfBDaC0ychMvsh11JmsYVMZNwW2VPLmDyoQXYFqi1m7AxCUy3P3VCeRn2SfMus=",
      "AccessKeyId": "STS.NTgSW8S1mZPsMwfV7Fc1CAeoj",
      "AccessKeySecret": "8ymT7djRJQxocsfnvDvjZKKFY5UPmtPewXdwmXnyHQX9",
      "Expiration": "2021-11-08T08:49:04Z"
    };
    return BetterAliyunOssCredentials.fromMap(credentials);
  }
}
