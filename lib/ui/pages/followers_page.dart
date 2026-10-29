import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'user_page.dart';

/// 我的粉丝：站点 `home.php?mod=follow&do=follower` 的原生列表。
///
/// 每行显示头像、昵称与「关注 / 粉丝」数量，点击进入对方主页；
/// 不再把「6 关注」这种计数链接当成昵称渲染。
class FollowersPage extends StatefulWidget {
  const FollowersPage({super.key});

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  final ScrollController _scroll = ScrollController();
  List<FriendItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final state = AppState.instance;
    if (!state.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var uid = state.profile?.uid ?? 0;
      if (uid <= 0) {
        await state.refreshProfile(silent: true);
        uid = AppState.instance.profile?.uid ?? 0;
      }
      if (uid <= 0) throw SiteException('无法识别当前账号，请刷新个人资料后重试');
      final items = await state.repo.fetchFollowers(uid);
      if (!mounted) return;
      setState(() {
        _items = items;
        _page = 1;
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载粉丝列表失败，请稍后重试';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final uid = AppState.instance.profile?.uid ?? 0;
    if (uid <= 0) return;
    setState(() => _loadingMore = true);
    try {
      final next = await AppState.instance.repo.fetchFollowers(uid, page: _page + 1);
      if (!mounted) return;
      setState(() {
        final known = _items.map((item) => item.uid).toSet();
        final fresh = next.where((item) => known.add(item.uid)).toList();
        if (fresh.isNotEmpty) {
          _items = [..._items, ...fresh];
          _page += 1;
          _hasMore = true;
        } else {
          _hasMore = false;
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) await _load();
  }

  void _openUser(FriendItem user) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserPage(uid: user.uid, name: user.username)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的粉丝'),
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
                                  EmptyView(text: '还没有粉丝', icon: Icons.people_outline_rounded),
                                ],
                              )
                            : ListView.separated(
                                controller: _scroll,
                                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                padding: const EdgeInsets.only(bottom: 24),
                                itemCount: _items.length + (_loadingMore ? 1 : 0),
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  indent: 74,
                                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                                ),
                                itemBuilder: (context, index) {
                                  if (index >= _items.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 18),
                                      child: Center(child: SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )),
                                    );
                                  }
                                  return _row(scheme, _items[index]);
                                },
                              ),
                      ),
      ),
    );
  }

  Widget _row(ColorScheme scheme, FriendItem user) {
    final stats = <String>[
      if (user.following > 0) '关注 ${user.following}',
      if (user.followers > 0) '粉丝 ${user.followers}',
    ];
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      leading: UserAvatar(url: user.avatar, name: user.username, size: 44),
      title: Text(
        user.username,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        stats.isEmpty ? 'UID ${user.uid}' : stats.join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, color: scheme.outline),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.outline),
      onTap: () => _openUser(user),
    );
  }

  Widget _loginHint(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline_rounded, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('登录后查看我的粉丝', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}
