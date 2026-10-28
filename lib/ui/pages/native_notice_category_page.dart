import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'thread_page.dart';
import 'user_page.dart';

/// 原生消息分类页：请求论坛 HTML 数据，但列表、空状态、错误处理和跳转均由 Flutter 绘制。
class NativeNoticeCategoryPage extends StatefulWidget {
  const NativeNoticeCategoryPage({
    super.key,
    required this.title,
    required this.path,
    this.kind = NoticeKind.notifications,
  });

  final String title;
  final String path;
  final NoticeKind kind;

  @override
  State<NativeNoticeCategoryPage> createState() => _NativeNoticeCategoryPageState();
}

enum NoticeKind { notifications, followers }

class _NoticeItem {
  const _NoticeItem({
    required this.title,
    required this.content,
    required this.time,
    required this.url,
    this.uid = 0,
    this.tid = 0,
    this.avatar = '',
    this.unread = false,
  });

  final String title;
  final String content;
  final String time;
  final String url;
  final int uid;
  final int tid;
  final String avatar;
  final bool unread;
}

class _NativeNoticeCategoryPageState extends State<NativeNoticeCategoryPage> {
  List<_NoticeItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      if (!mounted) return;
      setState(() { _loading = false; _error = null; _items = const []; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final response = await HttpSession.instance.get(widget.path);
      if (!response.ok) throw SiteException('加载失败（HTTP ${response.statusCode}）');
      final doc = html_parser.parse(response.body);
      final items = <_NoticeItem>[];
      final seen = <String>{};
      final selectors = widget.kind == NoticeKind.followers
          ? 'li, .bbda, .comiis_uitem, .followlist, .space_list, .bm_c tr'
          : '.comiis_notice li, .notice li, .ntc_body li, .bbda, .comiis_uitem, .space_list, .noticeitem, .bm_c tr';
      for (final node in doc.querySelectorAll(selectors)) {
        final text = _clean(node.text);
        if (text.length < 2 || text.length > 1200) continue;
        final anchors = node.querySelectorAll('a[href]');
        if (anchors.isEmpty) continue;
        String url = '';
        String label = '';
        for (final a in anchors) {
          final href = a.attributes['href'] ?? '';
          final t = _clean(a.text);
          if (href.isEmpty || href.startsWith('javascript:') || t.isEmpty) continue;
          if (url.isEmpty) { url = href; label = t; }
          if (RegExp(r'(tid=\d+|forum\.php\?mod=viewthread|thread-\d+-\d+-\d+\.html)').hasMatch(href)) {
            url = href;
            if (t.isNotEmpty) label = t;
            break;
          }
        }
        if (url.isEmpty) continue;
        final absolute = AppConfig.uri(url).toString();
        if (!seen.add(absolute)) continue;
        final tid = int.tryParse(RegExp(r'[?&]tid=(\d+)').firstMatch(url)?.group(1) ??
            RegExp(r'thread-(\d+)-').firstMatch(url)?.group(1) ?? '') ?? 0;
        final uid = int.tryParse(RegExp(r'[?&]uid=(\d+)').firstMatch(url)?.group(1) ??
            RegExp(r'space-(\d+)-').firstMatch(url)?.group(1) ?? '') ?? 0;
        final avatarNode = node.querySelector('img');
        final timeNode = node.querySelector('time, .xg1, .time, .dateline, .grey');
        final body = text.replaceFirst(label, '').trim();
        items.add(_NoticeItem(
          title: label.isEmpty ? widget.title : label,
          content: body.isEmpty ? text : body,
          time: _clean(timeNode?.text ?? ''),
          url: absolute,
          tid: tid,
          uid: uid,
          avatar: AppConfig.uri(avatarNode?.attributes['src'] ?? '').toString(),
          unread: node.classes.any((c) => c.contains('new') || c.contains('unread')) ||
              node.querySelector('.new, .unread, em.new') != null,
        ));
      }
      // Some Discuz pages render rows as cards/divs rather than list items.
      if (items.isEmpty && widget.kind == NoticeKind.notifications) {
        for (final a in doc.querySelectorAll('a[href*="tid="], a[href*="thread-"]')) {
          final href = a.attributes['href'] ?? '';
          final label = _clean(a.text);
          if (label.isEmpty || label.length > 180) continue;
          final absolute = AppConfig.uri(href).toString();
          if (!seen.add(absolute)) continue;
          final tid = int.tryParse(RegExp(r'[?&]tid=(\d+)').firstMatch(href)?.group(1) ??
              RegExp(r'thread-(\d+)-').firstMatch(href)?.group(1) ?? '') ?? 0;
          items.add(_NoticeItem(title: label, content: '', time: '', url: absolute, tid: tid));
        }
      }
      if (!mounted) return;
      setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载消息失败，请检查网络后重试';
      });
    }
  }

  String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) await _load();
  }

  void _openItem(_NoticeItem item) {
    if (item.tid > 0) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ThreadPage(tid: item.tid, title: item.title),
      ));
    } else if (item.uid > 0) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UserPage(uid: item.uid, name: item.title),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂时无法识别这条消息的目标页面')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [if (AppState.instance.isLoggedIn)
          IconButton(tooltip: '刷新', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: !AppState.instance.isLoggedIn
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.notifications_none_rounded, size: 48, color: scheme.outline),
              const SizedBox(height: 12),
              const Text('登录后查看消息提醒'),
              const SizedBox(height: 16),
              FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
            ]))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                              const SizedBox(height: 150),
                              Icon(widget.kind == NoticeKind.followers ? Icons.group_outlined : Icons.notifications_off_outlined,
                                  size: 48, color: scheme.outline),
                              const SizedBox(height: 12),
                              Center(child: Text(widget.kind == NoticeKind.followers ? '暂时没有新的粉丝记录' : '暂无消息提醒',
                                  style: TextStyle(color: scheme.onSurfaceVariant))),
                            ])
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => Divider(height: 1, indent: 76,
                                  color: scheme.outlineVariant.withValues(alpha: .45)),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                  leading: widget.kind == NoticeKind.followers
                                      ? UserAvatar(url: item.avatar, name: item.title, size: 44)
                                      : CircleAvatar(
                                          backgroundColor: item.unread ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                                          child: Icon(item.unread ? Icons.markunread_rounded : Icons.notifications_none_rounded,
                                              color: item.unread ? scheme.primary : scheme.onSurfaceVariant)),
                                  title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 14, fontWeight: item.unread ? FontWeight.w700 : FontWeight.w500)),
                                  subtitle: item.content.isEmpty ? null : Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(item.content, maxLines: 3, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                  ),
                                  trailing: item.time.isEmpty ? const Icon(Icons.chevron_right_rounded) :
                                      SizedBox(width: 74, child: Text(item.time, textAlign: TextAlign.end,
                                        maxLines: 2, style: TextStyle(fontSize: 10, color: scheme.outline))),
                                  onTap: () => _openItem(item),
                                );
                              },
                            ),
                    ),
    );
  }
}
