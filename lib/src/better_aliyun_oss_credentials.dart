/// 阿里云签名
class BetterAliyunOssCredentials {
  late String accessKeyId;
  late String accessKeySecret;
  late String securityToken;
  late DateTime expiration;

  BetterAliyunOssCredentials();

  BetterAliyunOssCredentials.init({required this.accessKeyId, required this.accessKeySecret, required this.securityToken, required this.expiration});

  factory BetterAliyunOssCredentials.fromMap(Map<String, dynamic> json) {
    final data = BetterAliyunOssCredentials();

    if (json['AccessKeyId'] != null) {
      data.accessKeyId = json['AccessKeyId'].toString();
    }
    if (json['AccessKeySecret'] != null) {
      data.accessKeySecret = json['AccessKeySecret'].toString();
    }
    if (json['SecurityToken'] != null) {
      data.securityToken = json['SecurityToken'].toString();
    }
    if (json['Expiration'] != null) {
      data.expiration = DateTime.tryParse(json['Expiration'].toString()) ?? DateTime.now();
    }

    return data;
  }
}
