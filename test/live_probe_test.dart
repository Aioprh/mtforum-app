import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/app_config.dart';
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

Future<String> _editHtml() async {
  final r = await HttpSession.instance.get('forum.php', query: {
    'mod': 'post',
    'action': 'edit',
    'fid': '$_fid',
    'tid': '$_tid',
    'pid': '$_pid',
    'mobile': 'no',
  });
  return r.body;
}

Set<int> _aids(String html) {
  final out = <int>{};
  for (final p in [r'imageattach(\d+)', r'attachname(\d+)', r'id="attach_(\d+)"']) {
    for (final m in RegExp(p).allMatches(html)) {
      final v = int.tryParse(m.group(1)!);
      if (v != null) out.add(v);
    }
  }
  return out;
}

void main() {
  test('upload then locate aid from page', () async {
    _loadCookies();
    final repo = ForumRepository.instance;

    final draft = await repo.fetchEditDraft(tid: _tid, pid: _pid, fid: _fid);
    final before = _aids(await _editHtml());
    print('AIDS_BEFORE $before');

    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final referer = AppConfig.uri('forum.php', {
      'mod': 'post',
      'action': 'edit',
      'fid': '$_fid',
      'tid': '$_tid',
      'pid': '$_pid',
      'mobile': 'no',
    }).toString();
    final name = 'probe_del_${DateTime.now().millisecondsSinceEpoch}.png';
    final res = await HttpSession.instance.postFile(
      'misc.php',
      query: {
        'mod': 'swfupload',
        'action': 'swfupload',
        'operation': 'upload',
        'type': 'image',
        'fid': '$_fid',
        'tid': '$_tid',
        'pid': '$_pid',
        'uid': '${draft.uid}',
        'hash': draft.uploadHash,
        'simple': '2',
        'inajax': 'yes',
        'infloat': 'yes',
      },
      field: 'Filedata',
      filename: name,
      bytes: png,
      fields: {
        'uid': '${draft.uid}',
        'hash': draft.uploadHash,
        'fid': '$_fid',
        'tid': '$_tid',
        'pid': '$_pid',
      },
      referer: referer,
    );
    print('RAW ${res.body.replaceAll('\n', ' ').replaceAll('\r', ' ')}');

    final html = await _editHtml();
    final after = _aids(html);
    print('AIDS_AFTER $after');
    print('NEW_AIDS ${after.difference(before)}');

    final idx = html.indexOf('unusedattach');
    if (idx > 0) {
      final end = idx + 1200 > html.length ? html.length : idx + 1200;
      print('UNUSED ${html.substring(idx, end).replaceAll('\n', ' ')}');
    }
    print('DRAFT_ATT ${draft.attachments.map((a) => a.aid).toList()}');
    exit(0);
  });
}
