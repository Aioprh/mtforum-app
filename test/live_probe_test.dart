import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/http_session.dart';
import 'package:mt_forum/data/forum_repository.dart';

const String _cookieRaw = String.fromEnvironment('MT_COOKIE');
const String _origB64 =
    '44CQ6Z2eTVTlrpjmlrnjgJEKCuabtOaWsOaXpeW/l++8mgoK6KGl5YWo5aSn6YOo5YiG5Yqf6IO977yM5L+u5aSN5LiA5aCGYnVnCgpwc++8muebruWJjeW3sue7j+eul+aYr+WujOe+juS6hgoK5LiL6L296L+e5o6l77yaW2hpZGVdaHR0cHM6Ly9zaGFyZS5mZWlqaXBhbi5jb20vcy9qenl3VjhOb1svaGlkZV0=';

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
  test('restore original body', () async {
    _loadCookies();
    final repo = ForumRepository.instance;
    final draft = await repo.fetchEditDraft(tid: 176076, pid: 12089521, fid: 42);
    final original = utf8.decode(base64Decode(_origB64));
    print('CURRENT ${jsonEncode(draft.message)}');
    print('TARGET  ${jsonEncode(original)}');
    if (draft.message.trim() == original.trim()) {
      print('ALREADY OK');
      exit(0);
    }
    final r = await repo.editPost(
      fid: 42,
      tid: 176076,
      pid: 12089521,
      subject: draft.subject,
      message: original,
      formhash: draft.formhash,
      extraForm: draft.extraForm,
    );
    print('RESTORE $r');
    final again = await repo.fetchEditDraft(tid: 176076, pid: 12089521, fid: 42);
    print('AFTER len=${again.message.length} same=${again.message.trim() == original.trim()}');
    print('ATT ${again.attachments.map((a) => a.aid).toList()}');
    exit(0);
  });
}
