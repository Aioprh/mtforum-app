import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/http_session.dart';
import 'package:mt_forum/data/forum_repository.dart';

const String _cookieRaw = String.fromEnvironment('MT_COOKIE');
const int _tid = 176076;
const int _pid = 12089521;
const int _fid = 42;

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
  test('deleteattach responses', () async {
    _loadCookies();
    final repo = ForumRepository.instance;
    final draft = await repo.fetchEditDraft(tid: _tid, pid: _pid, fid: _fid);
    print('FORMHASH ${draft.formhash}');

    for (final aid in [1, 9, 382585]) {
      final r = await HttpSession.instance.get('forum.php', query: {
        'mod': 'ajax',
        'action': 'deleteattach',
        'inajax': 'yes',
        'formhash': draft.formhash,
        'tid': '$_tid',
        'pid': '$_pid',
        'aids[]': '$aid',
      }, referer: 'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=$_tid');
      print('AID $aid status=${r.statusCode} uri=${r.uri}');
      print('AID $aid body=${r.body.replaceAll('\n', ' ').replaceAll('\r', ' ').substring(0, r.body.length > 400 ? 400 : r.body.length)}');
    }
    exit(0);
  });
}
