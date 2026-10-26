import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'pm_chat_page.dart';
import 'user_page.dart';

/// 我的好友：好友列表，可进入主页或直接私聊。
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final List<FriendItem> _items = [];
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
      final items = await AppState.instance.repo.fetchFriends();
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
        _error = e is SiteException ? e.message : '加载好友列表失败，请稍后重试';
      });
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) await _load();
  }

  void _openUser(FriendItem friend) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserPage(uid: friend.uid, name: friend.username)),
    );
  }

  void _openChat(FriendItem friend) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PmChatPage(uid: friend.uid, name: friend.username)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的好友'),
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
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                children: const [
                                  SizedBox(height: 90),
                                  EmptyView(text: '你还没有好友', icon: Icons.group_outlined),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                                ),
                                itemBuilder: (context, index) {
                                  final friend = _items[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    leading: UserAvatar(
                                      url: friend.avatar,
                                      name: friend.username,
                                      size: 44,
                                    ),
                                    title: Text(
                                      friend.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: friend.note.isEmpty
                                        ? Text(
                                            'UID ${friend.uid}',
                                            style: TextStyle(fontSize: 10.5, color: scheme.outline),
                                          )
                                        : Text(
                                            friend.note,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 10.5, color: scheme.outline),
                                          ),
                                    trailing: IconButton(
                                      tooltip: '发私信',
                                      onPressed: () => _openChat(friend),
                                      icon: Icon(
                                        Icons.mail_outline_rounded,
                                        size: 20,
                                        color: scheme.primary,
                                      ),
                                    ),
                                    onTap: () => _openUser(friend),
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
          Icon(Icons.group_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('登录后查看我的好友', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}
