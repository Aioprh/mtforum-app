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

String clip(String s, int idx, int before, int after) {
  final a = idx - before < 0 ? 0 : idx - before;
  final b = idx + after > s.length ? s.length : idx + after;
  return s.substring(a, b).replaceAll('\n', ' ');
}

void main() {
  test('delAttach implementation', () async {
    _loadCookies();
    final http = HttpSession.instance;

    final js = await http.get('static/js/post.js');
    print('JS status=${js.statusCode} len=${js.body.length}');
    final k = js.body.indexOf('delAttach');
    print('JS_HAS ${k > 0}');
    if (k > 0) print('JS_BODY ${clip(js.body, k, 200, 1800)}');

    final page = await http.get('forum.php', query: {
      'mod': 'post',
      'action': 'edit',
      'fid': '42',
      'tid': '176076',
      'pid': '12089521',
      'mobile': 'no',
    });
    final html = page.body;
    final a = html.indexOf('attach_382585');
    print('MARK attach_382585 at $a');
    if (a > 0) print('CARD ${clip(html, a, 900, 900)}');
    final b = html.indexOf('attachlist');
    print('ATTACHLIST ${clip(html, b, 100, 2600)}');
    exit(0);
  });
}
