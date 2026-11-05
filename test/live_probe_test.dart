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

void dump(String tag, List<dynamic> list) {
  print('$tag n=${list.length} ${list.map((a) => '${a.aid}:${a.name}:del=${a.deletable}').join(' | ')}');
}

void main() {
  test('delete existing attachment end to end', () async {
    _loadCookies();
    final repo = ForumRepository.instance;

    var draft = await repo.fetchEditDraft(tid: _tid, pid: _pid, fid: _fid);
    final original = draft.message;
    print('ORIG len=${original.length} b64=${base64Encode(utf8.encode(original))}');
    dump('BEFORE', draft.attachments);

    // 1x1 png
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
    final aid = await repo.uploadAttachment(
      bytes: png,
      filename: 'probe_del_${DateTime.now().millisecondsSinceEpoch}.png',
      uploadHash: draft.uploadHash,
      uid: draft.uid,
      referer: referer,
      image: true,
      fid: _fid,
      tid: _tid,
      pid: _pid,
    );
    print('UPLOAD aid=$aid');

    final tagged = '${original.trim()}\n\n[attachimg]$aid[/attachimg]';
    final save1 = await repo.editPost(
      fid: _fid,
      tid: _tid,
      pid: _pid,
      subject: draft.subject,
      message: tagged,
      formhash: draft.formhash,
      attachmentIds: [aid],
      extraForm: draft.extraForm,
    );
    print('SAVE1 $save1');

    draft = await repo.fetchEditDraft(tid: _tid, pid: _pid, fid: _fid);
    dump('AFTER_UPLOAD', draft.attachments);
    final target = draft.attachments.indexWhere((a) => a.aid == aid);
    if (target < 0) {
      print('TEMP ATTACHMENT NOT FOUND, abort');
      exit(0);
    }

    try {
      final msg = await repo.deleteAttachment(
        aid: aid,
        tid: _tid,
        pid: _pid,
        formhash: draft.formhash,
      );
      print('DELETE $msg');
    } catch (e) {
      print('DELETE FAILED $e');
    }

    draft = await repo.fetchEditDraft(tid: _tid, pid: _pid, fid: _fid);
    dump('AFTER_DELETE', draft.attachments);
    print('STILL_HAS ${draft.attachments.any((a) => a.aid == aid)}');

    final save2 = await repo.editPost(
      fid: _fid,
      tid: _tid,
      pid: _pid,
      subject: draft.subject,
      message: original,
      formhash: draft.formhash,
      extraForm: draft.extraForm,
    );
    print('SAVE2 $save2');
    draft = await repo.fetchEditDraft(tid: _tid, pid: _pid, fid: _fid);
    print('FINAL len=${draft.message.length} same=${draft.message.trim() == original.trim()}');
    dump('FINAL', draft.attachments);
    exit(0);
  });
}
