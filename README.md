# better_aliyun_oss

A Simple Aliyun OSS Upload for Flutter.

## Install Started

1. Add this to your **pubspec.yaml** file:

```yaml
dependencies:
  better_aliyun_oss: ^0.0.7
```

2. Install it

```bash
$ flutter packages get
```

## Normal usage

```dart
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
  
  Future<BetterAliyunOssCredentials?> credentials() async {
    final credentials = {
      "SecurityToken": "",
      "AccessKeyId": "",
      "AccessKeySecret": "",
      "Expiration": "",
    };
    return BetterAliyunOssCredentials.fromMap(credentials);
  }

  void uploading() async {
    final objectFileName = Uuid().v1().replaceAll("-", "") + path.extension(file.path);
    final objectPath = "image/${DateFormat("yyyyMM").format(DateTime.now())}/$objectFileName";

    simplePutRequest = ossClient.putObject(
      bucket: () async => "my-bucket",
      endpoint: () async => "oss-cn-hangzhou.aliyuncs.com",
      domain: () async => "https://domain.com",
      objectPath: objectPath,
      contentType: lookupMimeType(file.path) ?? "application/octet-stream",
      path: file.path,
    );

    print("简单数据上传请求 id : ${simplePutRequest.requestTaskId}");
  }
  
  void cancelSimpleUpload() {
    if (simplePutRequest != null) {
      ossClient.cancelPutObject(simplePutRequest!);
    }
  }
```

## Feature
- [x] simple upload file to Aliyun OSS.
- [x] multipart upload file to Aliyun OSS.

