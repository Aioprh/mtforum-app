import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import 'login_page.dart';
import 'thread_page.dart';

/// 消息通知：回复提醒、@提醒与系统通知。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<NoticeItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = null;
        _items.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppState.instance.repo.fetchNotices();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载失败，请稍后重试';
      });
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) _load();
  }

  void _openItem(NoticeItem item) {
    final thread = RegExp(r'thread-(\d+)-\d+-\d+\.html').firstMatch(item.url);
    if (thread != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ThreadPage(tid: int.parse(thread.group(1)!))),
      );
      return;
    }
    final tid = RegExp(r'[?&]tid=(\d+)').firstMatch(item.url)?.group(1);
    if (tid != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThreadPage(tid: int.parse(tid))));
      return;
    }
    if (item.url.isNotEmpty) {
      launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息通知'),
        actions: [
          if (AppState.instance.isLoggedIn)
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !AppState.instance.isLoggedIn
            ? _loginHint(scheme)
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                children: const [
                                  SizedBox(height: 90),
                                  EmptyView(text: '暂无消息通知'),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 10,
                                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    tileColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                    leading: Icon(Icons.notifications_none_rounded, color: scheme.primary),
                                    title: Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                                    ),
                                    subtitle: item.time.isEmpty
                                        ? null
                                        : Padding(
                                            padding: const EdgeInsets.only(top: 3),
                                            child: Text(item.time, style: TextStyle(fontSize: 10.5, color: scheme.outline)),
                                          ),
                                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: scheme.outline),
                                    onTap: () => _openItem(item),
                                  );
                                },
                              ),
                      ),
      ),
    );
  }

  Widget _loginHint(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_off_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('登录后查看回复与 @ 提醒', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}
