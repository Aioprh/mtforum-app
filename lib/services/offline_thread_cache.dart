import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models.dart';

class OfflineThreadCache {
  OfflineThreadCache._();
  static final instance = OfflineThreadCache._();
  static const _key = 'mt_forum_offline_threads_v1';

  Future<Map<String, dynamic>> _read() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final value = jsonDecode(raw);
      if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    return {};
  }

  Future<List<Map<String, dynamic>>> list() async {
    final data = await _read();
    final items = data.values.whereType<Map>().map((v) => v.map((k, v) => MapEntry(k.toString(), v))).toList();
    items.sort((a, b) => (b['cachedAt'] ?? '').toString().compareTo((a['cachedAt'] ?? '').toString()));
    return items;
  }

  Future<void> save({required int tid, required String title, required String boardName, required String author, required String time, required int views, required int replies, required List<ForumPost> posts}) async {
    final data = await _read();
    data['$tid'] = {
      'tid': tid, 'title': title, 'boardName': boardName, 'author': author, 'time': time,
      'views': views, 'replies': replies, 'cachedAt': DateTime.now().toIso8601String(),
      'posts': posts.map((p) => {
        'pid': p.pid, 'author': p.author, 'avatar': p.avatar, 'time': p.time, 'html': p.html,
        'floor': p.floor, 'uid': p.uid, 'level': p.level, 'location': p.location,
        'isOp': p.isOp, 'likes': p.likes, 'images': p.images,
        'comments': p.comments.map((c) => {'author': c.author, 'text': c.text, 'uid': c.uid, 'time': c.time}).toList(),
      }).toList(),
    };
    if (!await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(data))) {
      throw StateError('Unable to persist offline cache');
    }
  }

  Future<void> delete(int tid) async {
    final data = await _read(); data.remove('$tid');
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(data));
  }
  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
  int estimateBytes(Map<String, dynamic> item) => utf8.encode(jsonEncode(item)).length;
}
