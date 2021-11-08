#import "BetterAliyunOssPlugin.h"

@implementation BetterAliyunOssPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel methodChannelWithName:@"better_aliyun_oss" binaryMessenger:[registrar messenger]];
  BetterAliyunOssPlugin* instance = [[BetterAliyunOssPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  result(FlutterMethodNotImplemented);
}

@end
