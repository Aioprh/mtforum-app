import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/app_config.dart';
import 'package:mt_forum/core/http_session.dart';
import 'package:mt_forum/core/upload_result.dart';
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
  test('raw upload response', () async {
    _loadCookies();
    final repo = ForumRepository.instance;
    final draft = await repo.fetchEditDraft(tid: _tid, pid: _pid, fid: _fid);
    for (final a in draft.attachments) {
      print('ATT ${a.aid} img=${a.isImage} del=${a.deletable} name=${a.name}');
    }

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
    print('RAW status=${res.statusCode} body=${res.body.replaceAll('\n', ' ').replaceAll('\r', ' ')}');

    final parsed = parseUploadResult(res.body);
    print('PARSED aid=${parsed?.aid} err=${parsed?.errorCode} file=${parsed?.attachment} name=${parsed?.filename}');
    exit(0);
  });
}
