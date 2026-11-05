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
  test('attach delete link + forum_post.js', () async {
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
    final i = html.indexOf('<td class="attc"><a href');
    print('DEL_LINK ${html.substring(i, i + 420).replaceAll('\n', ' ')}');

    final js = await http.get('static/js/forum_post.js');
    print('JS len=${js.body.length} status=${js.statusCode}');
    for (final key in ['attachupdate', 'delattachop']) {
      var k = js.body.indexOf(key);
      var n = 0;
      while (k > 0 && n < 3) {
        final a = k - 320 < 0 ? 0 : k - 320;
        final b = k + 420 > js.body.length ? js.body.length : k + 420;
        print('JSCTX $key ${js.body.substring(a, b).replaceAll('\n', ' ')}');
        k = js.body.indexOf(key, k + 1);
        n++;
      }
    }
    exit(0);
  });
}
