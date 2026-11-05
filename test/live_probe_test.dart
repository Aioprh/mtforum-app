import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/http_session.dart';
import 'package:mt_forum/data/forum_repository.dart';

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
  test('check attachments now', () async {
    _loadCookies();
    final repo = ForumRepository.instance;
    final draft = await repo.fetchEditDraft(tid: 176076, pid: 12089521, fid: 42);
    print('ATT_N ${draft.attachments.length}');
    for (final a in draft.attachments) {
      print('ATT ${a.aid} ${a.name} ${a.sizeText} del=${a.deletable}');
    }
    print('MSG len=${draft.message.length}');
    final r = await HttpSession.instance.get('forum.php', query: {'mod': 'viewthread', 'tid': '176076'});
    print('THREAD len=${r.body.length} has382585=${r.body.contains('382585')} has382627=${r.body.contains('382627')}');
    exit(0);
  });
}
