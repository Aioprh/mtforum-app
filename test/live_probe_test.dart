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
  test('inspect edit page attachments', () async {
    _loadCookies();
    final http = HttpSession.instance;

    final thread = await http.get('forum.php', query: {'mod': 'viewthread', 'tid': '176076'});
    final pid = RegExp(r'id="post_(\d+)"').firstMatch(thread.body)?.group(1);
    print('THREAD status=${thread.statusCode} pid=$pid len=${thread.body.length}');
    if (pid == null) {
      exit(0);
    }

    final page = await http.get('forum.php', query: {
      'mod': 'post',
      'action': 'edit',
      'fid': '42',
      'tid': '176076',
      'pid': pid,
      'mobile': 'no',
    });
    print('EDIT status=${page.statusCode} len=${page.body.length}');
    final html = page.body;
    File('/tmp/edit.html').writeAsStringSync(html);

    // 所有和附件有关的 input
    for (final m in RegExp(r'<input[^>]*name="[^"]*attach[^"]*"[^>]*>').allMatches(html)) {
      print('INPUT ${m.group(0)}');
    }
    // 删除附件相关的链接 / 文本
    for (final m in RegExp(r'attachdel').allMatches(html)) {
      final s = m.start - 200 < 0 ? 0 : m.start - 200;
      final e = m.start + 260 > html.length ? html.length : m.start + 260;
      print('DELCTX ${html.substring(s, e).replaceAll('\n', ' ')}');
    }
    // 附件条目结构
    for (final key in ['imageattach', 'attachname', 'attachlist']) {
      final idx = html.indexOf(key);
      print('SEC $key at $idx');
      if (idx > 0) {
        final s = idx - 400 < 0 ? 0 : idx - 400;
        final e = idx + 1200 > html.length ? html.length : idx + 1200;
        print('SEC_BODY ${html.substring(s, e).replaceAll('\n', ' ')}');
      }
    }

    final draft = await ForumRepository.instance.fetchEditDraft(tid: 176076, pid: int.parse(pid), fid: 42);
    print('ATTACH n=${draft.attachments.length}');
    for (final a in draft.attachments) {
      print('ATT ${a.aid} img=${a.isImage} name=${a.name} size=${a.sizeText}');
    }
    exit(0);
  });
}
