/// 站点与全局常量。
class AppConfig {
  const AppConfig._();

  static const String appName = 'MT论坛';
  static const String host = 'bbs.binmt.cc';
  static const String base = 'https://bbs.binmt.cc/';
  static const String siteName = 'MT论坛';
  static const String version = '1.0.0';

  /// 移动端模板 UA（Discuz 会根据 mobile=2 返回原生布局）。
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  /// 官方公告版块。
  static const int announcementFid = 46;

  /// 首页每页条数（Discuz 移动端约 10 条）。
  static const int pageSize = 10;

  /// 详情页每页楼层数。
  static const int postsPerPage = 10;

  static Uri uri(String path, [Map<String, String>? query]) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final parsed = Uri.parse(path);
      if (query == null || query.isEmpty) return parsed;
      return parsed.replace(queryParameters: {...parsed.queryParameters, ...query});
    }
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$base$normalized').replace(queryParameters: query);
  }

  static bool isForumHost(String host) => host == AppConfig.host;
}
