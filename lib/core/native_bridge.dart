import 'package:flutter/services.dart';

/// 原生能力桥：系统分享、图片保存到相册。
class NativeBridge {
  const NativeBridge._();

  static const MethodChannel _channel = MethodChannel('cc.binmt.mt_forum/native');

  /// 本机首选 ABI，例如 `arm64-v8a`；取不到返回空串。
  static Future<String> supportedAbi() async {
    try {
      return await _channel.invokeMethod<String>('supportedAbi') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 把下载好的 APK 交给系统安装器。
  ///
  /// 复用 `openDownloadedFile`：原生那边已经按扩展名把 apk 单独走了
  /// ACTION_VIEW（直接开安装器，不弹「用什么打开」）。
  static Future<bool> installApk(String path, {String name = ''}) async {
    try {
      return await _channel.invokeMethod<bool>('openDownloadedFile', {
        'path': path,
        'name': name.isEmpty ? path.split('/').last : name,
      }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> shareText(String text) async {
    try {
      await _channel.invokeMethod<bool>('shareText', {'text': text});
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> saveImage(Uint8List bytes, {String name = 'mt_forum.jpg'}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('saveImage', {
        'bytes': bytes,
        'name': name,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
