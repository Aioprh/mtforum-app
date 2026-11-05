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
  test('delAttach function body', () async {
    _loadCookies();
    final js = await HttpSession.instance.get('static/js/forum_post.js');
    final body = js.body;
    final k = body.indexOf('function delAttach');
    print('AT $k');
    if (k > 0) print('BODY ${body.substring(k, k + 1600).replaceAll('\n', ' ')}');
    exit(0);
  });
}
