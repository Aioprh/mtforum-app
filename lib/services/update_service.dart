import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';

/// 发布包里的一个 APK。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;

  /// `app-arm64-v8a-release.apk` → `arm64-v8a`。
  String get abi {
    final lower = name.toLowerCase();
    if (lower.contains('arm64-v8a')) return 'arm64-v8a';
    if (lower.contains('armeabi-v7a')) return 'armeabi-v7a';
    if (lower.contains('x86_64')) return 'x86_64';
    if (lower.contains('x86')) return 'x86';
    return 'universal';
  }

  String get label => switch (abi) {
        'arm64-v8a' => 'ARM64（64 位，绝大多数手机）',
        'armeabi-v7a' => 'ARMv7（32 位老机型）',
        'x86_64' => 'x86_64（模拟器 / 少数平板）',
        'x86' => 'x86（旧模拟器）',
        _ => '通用包（体积大，任何机型都能装）',
      };

  String get sizeText {
    if (size <= 0) return '';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// GitHub 上的一次发布。
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.notes,
    required this.publishedAt,
    required this.assets,
  });

  final String tag;
  final String version;
  final String notes;
  final String publishedAt;
  final List<ReleaseAsset> assets;

  /// 按体积从小到大排，用户想省流量时好挑。
  List<ReleaseAsset> get apks =>
      assets.where((asset) => asset.name.toLowerCase().endsWith('.apk')).toList()
        ..sort((a, b) => a.size.compareTo(b.size));

  /// 本机架构对应的包；找不到就退回通用包。
  ReleaseAsset? assetFor(String abi) {
    for (final asset in apks) {
      if (asset.abi == abi) return asset;
    }
    for (final asset in apks) {
      if (asset.abi == 'universal') return asset;
    }
    return apks.isEmpty ? null : apks.first;
  }
}

class UpdateCheck {
  const UpdateCheck({this.release, this.error = ''});

  final AppRelease? release;
  final String error;

  bool get hasUpdate => release != null;
  bool get failed => error.isNotEmpty;
}

/// 检测 GitHub Releases 上的新版本。
///
/// 不走站点的 HttpSession：那份会话带着论坛 Cookie、还要过 WAF，拿去请求
/// api.github.com 只会添乱。这里单独用 http，匿名访问。
class UpdateService {
  const UpdateService._();

  static const String repo = 'Aioprh/mtforum-app';
  static const String _api = 'https://api.github.com/repos/$repo/releases/latest';

  /// 请求超时：慢网络下 12 秒足够，再久不如让用户重试。
  static const Duration timeout = Duration(seconds: 12);

  static const String _autoCheckKey = 'mt_forum_update_check_day';

  /// 启动时自动检查一天最多一次；返回 true 表示今天还没查过。
  ///
  /// 先把日期写进去再发起请求：网络失败也算查过，否则每次冷启动都去撞
  /// GitHub，反而更容易被限流。
  static Future<bool> claimAutoCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (prefs.getString(_autoCheckKey) == today) return false;
    await prefs.setString(_autoCheckKey, today);
    return true;
  }

  /// Releases 页的 atom 订阅，API 被限流时的退路。
  static const String _atom = 'https://github.com/$repo/releases.atom';

  /// GitHub API 匿名调用每小时只有 60 次，共享出口 IP 很容易撞上 403。
  /// 撞上就改读 atom：那里没有 assets 列表，但发布包的命名是固定的
  /// （CI 一直用 `app-<abi>-release.apk`），拼出来照样能下。
  static const List<String> _assetNames = [
    'app-arm64-v8a-release.apk',
    'app-armeabi-v7a-release.apk',
    'app-x86_64-release.apk',
    'app-release.apk',
  ];

  static Future<UpdateCheck> check({http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final api = await _checkViaApi(httpClient);
      if (!api.failed) return api;
      final fallback = await _checkViaAtom(httpClient);
      return fallback ?? api;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<UpdateCheck> _checkViaApi(http.Client client) async {
    try {
      final response = await client.get(
        Uri.parse(_api),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'MTForum-App',
        },
      ).timeout(timeout);
      if (response.statusCode == 404) {
        return const UpdateCheck(error: '仓库暂时没有发布版本');
      }
      if (response.statusCode == 403 || response.statusCode == 429) {
        return const UpdateCheck(error: 'GitHub 接口访问太频繁，稍后再试');
      }
      if (response.statusCode != 200) {
        return UpdateCheck(error: '检查更新失败（HTTP ${response.statusCode}）');
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) {
        return const UpdateCheck(error: '发布信息格式不对');
      }
      final release = parseRelease(json);
      if (release == null) return const UpdateCheck(error: '发布信息里没有安装包');
      return _verdict(release);
    } on Exception catch (error) {
      return UpdateCheck(error: '检查更新失败：${_short(error)}');
    }
  }

  static Future<UpdateCheck?> _checkViaAtom(http.Client client) async {
    try {
      final response = await client.get(
        Uri.parse(_atom),
        headers: const {'Accept': 'application/atom+xml', 'User-Agent': 'MTForum-App'},
      ).timeout(timeout);
      if (response.statusCode != 200) return null;
      final release = parseAtom(utf8.decode(response.bodyBytes));
      if (release == null) return null;
      return _verdict(release);
    } on Exception {
      return null;
    }
  }

  static UpdateCheck _verdict(AppRelease release) {
    if (compareVersions(release.version, AppConfig.version) <= 0) {
      return const UpdateCheck();
    }
    return UpdateCheck(release: release);
  }

  /// 解析 releases.atom 的第一条（最新一次发布）。
  @visibleForTesting
  static AppRelease? parseAtom(String body) {
    final entry = RegExp(r'<entry>([\s\S]*?)</entry>').firstMatch(body);
    if (entry == null) return null;
    final xml = entry.group(1)!;
    final link = RegExp(r'<link[^>]*rel="alternate"[^>]*href="([^"]+)"').firstMatch(xml) ??
        RegExp(r'<link[^>]*href="([^"]+)"[^>]*rel="alternate"').firstMatch(xml);
    final rawTitle = RegExp(r'<title[^>]*>([\s\S]*?)</title>').firstMatch(xml)?.group(1) ?? '';
    final tag = link == null
        ? rawTitle.replaceAll(RegExp(r'\s'), '').trim()
        : Uri.parse(link.group(1)!).pathSegments.last;
    final version = normalizeVersion(tag);
    if (version.isEmpty) return null;
    final rawContent = RegExp(r'<content[^>]*>([\s\S]*?)</content>').firstMatch(xml)?.group(1) ?? '';
    // atom 的 content 是「HTML 再实体转义」：先解一层拿到 HTML 源码，再
    // 让解析器去标签，才能得到干净的正文。
    final decoded = parser.parse('<div>$rawContent</div>').documentElement?.text ?? '';
    final notes = parser.parse('<div>$decoded</div>').documentElement?.text.trim() ?? '';
    final base = 'https://github.com/$repo/releases/download/$tag/';
    return AppRelease(
      tag: tag,
      version: version,
      notes: notes,
      publishedAt: RegExp(r'<updated>([^<]+)</updated>').firstMatch(xml)?.group(1)?.trim() ?? '',
      assets: [
        for (final name in _assetNames)
          ReleaseAsset(name: name, url: '$base$name', size: 0),
      ],
    );
  }

  /// 把 GitHub 的 JSON 转成 [AppRelease]；缺关键字段时返回 null。
  static AppRelease? parseRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final version = normalizeVersion(tag);
    if (version.isEmpty) return null;
    final rawAssets = json['assets'];
    final assets = <ReleaseAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) continue;
        final name = (item['name'] as String? ?? '').trim();
        final url = (item['browser_download_url'] as String? ?? '').trim();
        if (name.isEmpty || url.isEmpty) continue;
        assets.add(
          ReleaseAsset(
            name: name,
            url: url,
            size: (item['size'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }
    if (assets.isEmpty) return null;
    return AppRelease(
      tag: tag,
      version: version,
      notes: (json['body'] as String? ?? '').trim(),
      publishedAt: (json['published_at'] as String? ?? '').trim(),
      assets: assets,
    );
  }

  /// `v2.7.7` → `2.7.7`。
  static String normalizeVersion(String tag) =>
      tag.trim().replaceFirst(RegExp(r'^[vV]'), '');

  /// 逐段比较版本号，返回 1 / 0 / -1。
  ///
  /// 只按数字段比：`2.7.10` 要大于 `2.7.9`（字符串比会反过来）；段数不一致
  /// 时缺的位按 0 算，`2.8` 与 `2.8.0` 相等。带 `-beta` 之类后缀的段解析
  /// 失败就当 0，正式版仍然会排在预发布版前面。
  static int compareVersions(String a, String b) {
    final left = _parts(a);
    final right = _parts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }

  static List<int> _parts(String version) {
    final text = normalizeVersion(version).split('+').first;
    final segments = text.split('.');
    return segments.map((segment) {
      final match = RegExp(r'^\d+').firstMatch(segment);
      return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
    }).toList(growable: false);
  }

  static String _short(Object error) {
    final text = error.toString();
    if (text.contains('TimeoutException')) return '请求超时';
    if (text.contains('SocketException')) return '网络不可用';
    if (text.contains('HandshakeException')) return '证书校验失败';
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }
}
