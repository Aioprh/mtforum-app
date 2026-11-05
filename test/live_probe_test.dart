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
  test('attach row + post.js', () async {
    _loadCookies();
    final http = HttpSession.instance;
    final page = await http.get('forum.php', query: {
      'mod': 'post',
      'action': 'edit',
      'fid': '42',
      'tid': '176076',
      'pid': '12089521',
      'mobile': 'no',
    });
    final html = page.body;

    final start = html.indexOf('<tbody id="attach_382585">');
    final end = html.indexOf('</tbody>', start);
    print('ROW ${html.substring(start, end + 8).replaceAll('\n', ' ')}');

    // 页面引用的脚本
    for (final m in RegExp(r'<script[^>]*src="([^"]+)"[^>]*>').allMatches(html)) {
      final src = m.group(1)!;
      if (src.contains('post') || src.contains('common')) print('SCRIPT $src');
    }

    for (final name in ['post.js', 'common.js']) {
      for (final base in ['static/js/', 'https://cdn.binmt.cc/static/js/']) {
        final r = await http.get('$base$name');
        if (r.statusCode != 200) continue;
        final body = r.body;
        print('JS $base$name len=${body.length}');
        for (final key in ['delattachop', 'attachupdate', 'function delAttach']) {
          var i = body.indexOf(key);
          var n = 0;
          while (i > 0 && n < 2) {
            final a = i - 260 < 0 ? 0 : i - 260;
            final b = i + 420 > body.length ? body.length : i + 420;
            print('JSCTX $key ${body.substring(a, b).replaceAll('\n', ' ')}');
            i = body.indexOf(key, i + 1);
            n++;
          }
        }
        break;
      }
    }
    exit(0);
  });
}
