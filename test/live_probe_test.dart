import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/http_session.dart';

const String _cookieRaw = String.fromEnvironment('MT_COOKIE');

void _loadCookies() {
  final http = HttpSession.instance;
  for (final part in _cookieRaw.split('; ')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final name = part.substring(0, i);
    if (name == 'acw_tc' || name == 'cdn_sec_tc' || name == 'acw_sc__v2') continue;
    http.setCookie(name, part.substring(i + 1));
  }
}

void main() {
  test('probe thread page markers', () async {
    _loadCookies();
    final http = HttpSession.instance;
    final r = await http.get('forum.php', query: {'mod': 'viewthread', 'tid': '176076'});
    print('URL ${r.uri}');
    print('LEN ${r.body.length}');
    final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(r.body)?.group(1);
    print('TITLE $title');
    for (final p in [r'id="post_(\d+)"', r'id="pid(\d+)"', r'pid=(\d+)', r'postmessage_(\d+)']) {
      final ms = RegExp(p).allMatches(r.body).map((m) => m.group(1)).take(6).toList();
      print('MATCH $p => $ms');
    }
    final login = r.body.contains('登录') ? 'has-login-word' : 'no-login-word';
    print('LOGIN $login');
    exit(0);
  });
}
