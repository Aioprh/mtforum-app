import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/http_session.dart';

class DownloadRecord {
  const DownloadRecord({required this.url, required this.path, required this.name, required this.time});

  final String url;
  final String path;
  final String name;
  final String time;

  Map<String, String> toJson() => {'url': url, 'path': path, 'name': name, 'time': time};
  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
        url: json['url'] as String? ?? '',
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? 'download',
        time: json['time'] as String? ?? '',
      );
}

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();
  static const _key = 'mt_forum_download_history_v1';
  final List<DownloadRecord> records = [];
  bool initialized = false;

  Future<void> load() async {
    if (initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_key) ?? const <String>[];
    records
      ..clear()
      ..addAll(values.map((value) {
        try {
          return DownloadRecord.fromJson(jsonDecode(value) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<DownloadRecord>());
    initialized = true;
  }

  Future<DownloadRecord> download(String rawUrl, {void Function(int received, int total)? onProgress}) async {
    await load();
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
      throw const HttpException('不支持的下载地址');
    }
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/downloads');
    await folder.create(recursive: true);
    var name = Uri.decodeComponent(uri.pathSegments.isEmpty ? '' : uri.pathSegments.last);
    if (name.isEmpty || !name.contains('.')) name = 'download_${DateTime.now().millisecondsSinceEpoch}';
    name = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    var target = '${folder.path}/$name';
    if (await File(target).exists()) {
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      target = '${folder.path}/${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);
      request.headers.set(HttpHeaders.refererHeader, AppConfig.base);
      final cookie = HttpSession.instance.cookieHeader;
      if (cookie.isNotEmpty) request.headers.set(HttpHeaders.cookieHeader, cookie);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败：HTTP ${response.statusCode}', uri: uri);
      }
      final file = File(target).openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          file.add(chunk);
          received += chunk.length;
          onProgress?.call(received, response.contentLength);
        }
      } finally {
        await file.close();
      }
      final record = DownloadRecord(
        url: rawUrl,
        path: target,
        name: name,
        time: DateTime.now().toIso8601String(),
      );
      records.insert(0, record);
      await _save();
      return record;
    } catch (_) {
      final file = File(target);
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> remove(DownloadRecord record, {bool deleteFile = false}) async {
    records.remove(record);
    if (deleteFile) {
      final file = File(record.path);
      if (await file.exists()) await file.delete();
    }
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, records.map((record) => jsonEncode(record.toJson())).toList());
  }
}
