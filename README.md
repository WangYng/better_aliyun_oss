# better_aliyun_oss

A Simple Aliyun OSS Upload for Flutter.

## Install Started

1. Add this to your **pubspec.yaml** file:

```yaml
dependencies:
  better_aliyun_oss: ^0.0.3
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

  void uploading() async {
    final objectFileName = Uuid().v1().replaceAll("-", "") + path.extension(file.path);
    final objectPath = "image/${DateFormat("yyyyMM").format(DateTime.now())}/$objectFileName";

    final simplePutRequest = ossClient.putObject(
      bucket: "my-bucket",
      endpoint: "oss-cn-hangzhou.aliyuncs.com",
      domain: "https://domain.com",
      objectPath: objectPath,
      contentType: lookupMimeType(file.path) ?? "application/octet-stream",
      path: file.path,
    );

    print("简单数据上传请求 id : ${simplePutRequest.requestTaskId}");
  }
```

## Feature
- [x] simple upload file to Aliyun OSS.
- [x] multipart upload file to Aliyun OSS.

