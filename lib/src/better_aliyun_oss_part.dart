/// 阿里云分片信息
class BetterAliyunOssPart {
  late String bucket;
  late String endpoint;
  String? domain;
  late String objectPath;
  late String filePath;
  late String uploadId;
  late int partNumber;
  late int partRangeStart;
  late int partRangeLength;
  String? partETag;

  BetterAliyunOssPart();

  BetterAliyunOssPart.init({
    required this.bucket,
    required this.endpoint,
    this.domain,
    required this.objectPath,
    required this.filePath,
    required this.uploadId,
    required this.partNumber,
    required this.partRangeStart,
    required this.partRangeLength,
    this.partETag,
  });

  factory BetterAliyunOssPart.fromMap(Map<String, dynamic> json) {
    final data = BetterAliyunOssPart();

    if (json['bucket'] != null) {
      data.bucket = json['bucket'].toString();
    }
    if (json['endpoint'] != null) {
      data.endpoint = json['endpoint'].toString();
    }
    if (json['domain'] != null) {
      data.domain = json['domain'].toString();
    }
    if (json['objectPath'] != null) {
      data.objectPath = json['objectPath'].toString();
    }
    if (json['filePath'] != null) {
      data.filePath = json['filePath'].toString();
    }
    if (json['uploadId'] != null) {
      data.uploadId = json['uploadId'].toString();
    }
    if (json['partNumber'] != null) {
      if (json['partNumber'] is int) {
        data.partNumber = json['partNumber'].toInt();
      } else {
        data.partNumber = int.tryParse(json['partNumber'].toString()) ?? 0;
      }
    }
    if (json['partRangeStart'] != null) {
      if (json['partRangeStart'] is int) {
        data.partRangeStart = json['partRangeStart'].toInt();
      } else {
        data.partRangeStart = int.tryParse(json['partRangeStart'].toString()) ?? 0;
      }
    }
    if (json['partRangeLength'] != null) {
      if (json['partRangeLength'] is int) {
        data.partRangeLength = json['partRangeLength'].toInt();
      } else {
        data.partRangeLength = int.tryParse(json['partRangeLength'].toString()) ?? 0;
      }
    }
    if (json['partETag'] != null) {
      data.partETag = json['partETag'].toString();
    }
    return data;
  }

  @override
  String toString() {
    return 'BetterAliyunOssPart{bucket: $bucket, endpoint: $endpoint, domain: $domain, objectPath: $objectPath, filePath: $filePath,  uploadId: $uploadId, partNumber: $partNumber, partRangeStart: $partRangeStart, partRangeLength: $partRangeLength, partETag: $partETag}';
  }
}
