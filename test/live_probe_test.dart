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

String clip(String html, int idx, int before, int after) {
  final s = idx - before < 0 ? 0 : idx - before;
  final e = idx + after > html.length ? html.length : idx + after;
  return html.substring(s, e).replaceAll('\n', ' ');
}

void main() {
  test('edit page attach markup', () async {
    _loadCookies();
    final http = HttpSession.instance;
    const tid = 176076;
    const pid = 12089521;

    final page = await http.get('forum.php', query: {
      'mod': 'post',
      'action': 'edit',
      'fid': '42',
      'tid': '$tid',
      'pid': '$pid',
      'mobile': 'no',
    });
    final html = page.body;
    print('EDIT status=${page.statusCode} len=${html.length} url=${page.uri}');
    print('TITLE ${RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html)?.group(1)}');

    print('HAS_ATTDEL ${html.contains('attachdel')}');
    for (final m in RegExp(r'attachdel').allMatches(html)) {
      print('DELCTX ${clip(html, m.start, 240, 240)}');
    }
    for (final m in RegExp(r'<input[^>]*name="[^"]*attach[^"]*"[^>]*>').allMatches(html)) {
      print('INPUT ${m.group(0)}');
    }
    for (final key in ['imageattach', 'attachname', 'attachlist', 'delete']) {
      final idx = html.indexOf(key);
      print('SEC $key at $idx');
      if (idx > 0 && key != 'delete') print('SEC_BODY ${clip(html, idx, 300, 1400)}');
    }

    final draft = await ForumRepository.instance.fetchEditDraft(tid: tid, pid: pid, fid: 42);
    print('DRAFT attach=${draft.attachments.length} formhash=${draft.formhash} uid=${draft.uid} upHash=${draft.uploadHash.length} extra=${draft.extraForm.length}');
    for (final a in draft.attachments) {
      print('ATT ${a.aid} img=${a.isImage} name=${a.name} size=${a.sizeText}');
    }
    exit(0);
  });
}
