import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'user_page.dart';

/// 当前账号关注的用户列表。
class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  List<FriendItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
      final items = await state.repo.fetchFollowing(uid);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载关注列表失败，请稍后重试';
      });
    }
  }

  Future<void> _cancelFollowing(FriendItem user) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('取消关注'),
      content: Text('确定不再关注「${user.username}」吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('保留关注')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('取消关注')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    try {
      await AppState.instance.repo.cancelFollowing(user.uid);
      if (!mounted) return;
      setState(() => _items.removeWhere((item) => item.uid == user.uid));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消关注')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '取消关注失败')));
    }
  }

  Future<void> _editNote(FriendItem user) async {
    final controller = TextEditingController(text: user.note);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text('备注：${user.username}'),
      content: TextField(controller: controller, autofocus: true, maxLength: 30,
        decoration: const InputDecoration(labelText: '备注名称', hintText: '输入备注')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
      ],
    ));
    controller.dispose();
    if (value == null || !mounted) return;
    try {
      final saved = await AppState.instance.repo.setFollowingNote(user.uid, value);
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.uid == user.uid);
        if (i >= 0) {
          final x = _items[i];
          _items[i] = FriendItem(uid: x.uid, username: x.username, avatar: x.avatar, note: saved,
            followers: x.followers, following: x.following, isStarred: x.isStarred);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('备注已保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '保存备注失败')));
    }
  }

  Future<void> _toggleStar(FriendItem user) async {
    try {
      await AppState.instance.repo.setFollowingStar(user.uid, starred: !user.isStarred);
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.uid == user.uid);
        if (i >= 0) {
          final x = _items[i];
          _items[i] = FriendItem(uid: x.uid, username: x.username, avatar: x.avatar, note: x.note,
            followers: x.followers, following: x.following, isStarred: !x.isStarred);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(user.isStarred ? '已取消星标' : '已设为星标')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '星标操作失败')));
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
        title: const Text('我的关注'),
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
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 150),
                                  Icon(Icons.person_search_rounded, size: 48, color: scheme.outline),
                                  const SizedBox(height: 12),
                                  Center(
                                    child: Text(
                                      '还没有关注任何用户',
                                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  indent: 64,
                                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                                ),
                                itemBuilder: (context, index) {
                                  final user = _items[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    leading: UserAvatar(url: user.avatar, name: user.username, size: 44),
                                    title: Text(
                                      user.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                      user.followers > 0 || user.following > 0
                                          ? '关注 ${user.following}  ·  粉丝 ${user.followers}'
                                          : 'UID ${user.uid}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                                    ),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      IconButton(tooltip: '备注', visualDensity: VisualDensity.compact,
                                        onPressed: () => _editNote(user),
                                        icon: Icon(Icons.edit_note_rounded, color: scheme.primary)),
                                      IconButton(tooltip: user.isStarred ? '取消星标' : '星标',
                                        visualDensity: VisualDensity.compact, onPressed: () => _toggleStar(user),
                                        icon: Icon(user.isStarred ? Icons.star_rounded : Icons.star_outline_rounded,
                                          color: user.isStarred ? Colors.green : scheme.outline)),
                                      IconButton(tooltip: '取消关注', visualDensity: VisualDensity.compact,
                                        onPressed: () => _cancelFollowing(user),
                                        icon: const Icon(Icons.person_remove_alt_1_rounded, color: Colors.redAccent)),
                                    ]),
                                    onTap: () => _openUser(user),
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
          Icon(Icons.people_alt_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('登录后查看我的关注', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}
