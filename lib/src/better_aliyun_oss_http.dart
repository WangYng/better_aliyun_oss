
import 'package:dio/dio.dart';

class BetterAliyunOssDioUtils {
  static Dio? _instance;

  static Dio getInstance() {
    if (_instance == null) {
      _instance = Dio(BaseOptions(connectTimeout: 1000 * 30, receiveTimeout: 1000 * 30));

      _instance!.interceptors.add(LogInterceptor(request: true, responseBody: true));
    }

    return _instance!;
  }
}
