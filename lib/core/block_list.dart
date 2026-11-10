import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 被屏蔽的用户。
///
/// 站点自带的黑名单只影响「能否互动」，帖子和回复照样能看到，所以本地
/// 另存一份，渲染时直接把这些人的内容滤掉。[uid] 可能为 0（列表页偶尔
/// 拿不到作者 id），这时退回按用户名匹配。
class BlockedUser {
  const BlockedUser({required this.name, this.uid = 0, this.since = ''});

  final String name;
  final int uid;
  final String since;

  Map<String, dynamic> toJson() => {'name': name, 'uid': uid, 'since': since};

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        name: json['name'] as String? ?? '',
        uid: (json['uid'] as num?)?.toInt() ?? 0,
        since: json['since'] as String? ?? '',
      );
}

/// 本地屏蔽名单：屏蔽用户 + 评论关键词。
///
/// 只在本机生效，不上报站点。放在 core 而不是 AppState，是因为帖子列表、
/// 详情页、评论组件都要问一句「这条要不要显示」，走全局单例比层层传参省事。
class BlockList extends ChangeNotifier {
  BlockList._();

  static final BlockList instance = BlockList._();

  static const String _usersKey = 'mt_forum_blocked_users_v1';
  static const String _keywordsKey = 'mt_forum_blocked_keywords_v1';

  final List<BlockedUser> users = <BlockedUser>[];
  final List<String> keywords = <String>[];

  bool _loaded = false;

  /// 屏蔽页面上的统计、空状态都要等它。
  bool get loaded => _loaded;

  static Future<BlockList> ensureLoaded() async {
    await instance.load();
    return instance;
  }

  /// 只给测试用：清空内存状态，下次 [load] 重新读 mock 的偏好。
  @visibleForTesting
  void debugReset() {
    users.clear();
    keywords.clear();
    _loaded = false;
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final rawUsers = prefs.getStringList(_usersKey) ?? const <String>[];
    for (final raw in rawUsers) {
      try {
        final user = BlockedUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (user.name.trim().isNotEmpty) users.add(user);
      } catch (_) {
        // 坏掉的旧记录直接跳过，别让整份名单读不出来。
      }
    }
    final rawKeywords = prefs.getStringList(_keywordsKey) ?? const <String>[];
    for (final word in rawKeywords) {
      final text = word.trim();
      if (text.isNotEmpty && !keywords.contains(text)) keywords.add(text);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _usersKey,
      users.map((user) => jsonEncode(user.toJson())).toList(growable: false),
    );
    await prefs.setStringList(_keywordsKey, List<String>.from(keywords));
  }

  bool get isEmpty => users.isEmpty && keywords.isEmpty;

  // ---------------------------------------------------------------- 用户

  /// 某个作者是否在屏蔽名单里。
  ///
  /// uid 能对上就直接算命中；uid 缺失（0）或者站点换了 id 时按用户名兜底，
  /// 名字比较忽略大小写和首尾空白。
  bool blocksUser(String name, {int uid = 0}) {
    if (users.isEmpty) return false;
    final target = name.trim().toLowerCase();
    for (final user in users) {
      if (uid > 0 && user.uid > 0 && user.uid == uid) return true;
      if (target.isNotEmpty && user.name.trim().toLowerCase() == target) return true;
    }
    return false;
  }

  BlockedUser? userOf(String name, {int uid = 0}) {
    if (users.isEmpty) return null;
    final target = name.trim().toLowerCase();
    for (final user in users) {
      if (uid > 0 && user.uid > 0 && user.uid == uid) return user;
      if (target.isNotEmpty && user.name.trim().toLowerCase() == target) return user;
    }
    return null;
  }

  Future<bool> blockUser(String name, {int uid = 0}) async {
    final target = name.trim();
    if (target.isEmpty) return false;
    await load();
    if (userOf(target, uid: uid) != null) return false;
    users.insert(
      0,
      BlockedUser(name: target, uid: uid, since: _today()),
    );
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> unblockUser(BlockedUser user) async {
    await load();
    users.removeWhere((item) =>
        (user.uid > 0 && item.uid == user.uid) ||
        item.name.trim().toLowerCase() == user.name.trim().toLowerCase());
    await _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- 关键词

  /// 关键词命中：任一关键词出现在文本里就算。
  ///
  /// 英文忽略大小写，中文原样比较；空关键词永远不命中。
  bool blocksText(String text) {
    if (keywords.isEmpty || text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final word in keywords) {
      if (lower.contains(word.toLowerCase())) return true;
    }
    return false;
  }

  /// 楼层正文是 HTML，屏蔽判断得先转成纯文本。
  bool blocksHtml(String html) {
    if (keywords.isEmpty || html.isEmpty) return false;
    return blocksText(plainTextOf(html));
  }

  Future<bool> addKeyword(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) return false;
    await load();
    if (keywords.any((word) => word.toLowerCase() == text.toLowerCase())) {
      return false;
    }
    keywords.insert(0, text);
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> removeKeyword(String keyword) async {
    await load();
    keywords.removeWhere((word) => word.toLowerCase() == keyword.trim().toLowerCase());
    await _save();
    notifyListeners();
  }

  Future<void> clearKeywords() async {
    await load();
    keywords.clear();
    await _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- 工具

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static final RegExp _script = RegExp(r'<script[\s\S]*?</script>', caseSensitive: false);
  static final RegExp _style = RegExp(r'<style[\s\S]*?</style>', caseSensitive: false);
  static final RegExp _break = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final RegExp _tag = RegExp(r'<[^>]+>');
  static final RegExp _entity = RegExp(r'&(#\d+|#x[0-9a-f]+|[a-z]+);', caseSensitive: false);

  /// 粗略的 HTML 转纯文本，只服务于关键词匹配，不追求排版还原。
  static String plainTextOf(String html) {
    if (html.isEmpty) return '';
    var text = html
        .replaceAll(_script, ' ')
        .replaceAll(_style, ' ')
        .replaceAll(_break, '\n')
        .replaceAll(_tag, ' ');
    text = text.replaceAllMapped(_entity, (match) {
      final name = match.group(1)!;
      switch (name.toLowerCase()) {
        case 'nbsp':
          return ' ';
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      if (name.startsWith('#x') || name.startsWith('#X')) {
        final code = int.tryParse(name.substring(2), radix: 16);
        return code == null ? ' ' : String.fromCharCode(code);
      }
      if (name.startsWith('#')) {
        final code = int.tryParse(name.substring(1));
        return code == null ? ' ' : String.fromCharCode(code);
      }
      return ' ';
    });
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
