import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../data/forum_repository.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/thread_feed.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';

/// 他人主页：资料、关注、私信与 TA 的主题 / 回复。
class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.uid, this.name = ''});

  final int uid;
  final String name;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  UserProfile? _profile;
  String _hash = '';
  bool _loading = true;
  bool _followBusy = false;
  bool _following = false;
  String? _error;

  ForumRepository get _repo => AppState.instance.repo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.uid <= 0) {
      setState(() {
        _loading = false;
        _error = '无法识别用户';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (profile, hash) = await _repo.fetchUserProfile(widget.uid);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _hash = hash;
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

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    if (!AppState.instance.isLoggedIn) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _followBusy = true);
    try {
      final following = await _repo.followUser(uid: widget.uid, follow: !_following, hash: _hash);
      if (!mounted) return;
      setState(() => _following = following);
      _toast(following ? '已关注' : '已取消关注');
    } catch (e) {
      _toast(e is SiteException ? e.message : '操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPm() async {
    final uri = AppConfig.uri('home.php', {
      'mod': 'spacecp',
      'ac': 'pm',
      'op': 'showmsg',
      'handlekey': 'showmsg_${widget.uid}',
      'touid': '${widget.uid}',
      'mobile': '2',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _profile?.username.isNotEmpty == true ? _profile!.username : widget.name;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name.isEmpty ? '用户主页' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: '在浏览器打开',
              onPressed: () => launchUrl(
                AppConfig.uri('home.php', {'mod': 'space', 'uid': '${widget.uid}', 'do': 'profile', 'mobile': '2'}),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_browser_rounded),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : Column(
                    children: [
                      _header(scheme, name),
                      TabBar(
                        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        tabs: const [Tab(text: 'TA的主题'), Tab(text: 'TA的回复')],
                        indicatorColor: scheme.primary,
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            ThreadFeed(
                              loader: (page) => _repo.fetchUserThreads(widget.uid, page: page),
                              emptyText: 'TA 还没有发布过主题',
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                            ),
                            ThreadFeed(
                              loader: (page) => _repo.fetchUserReplies(widget.uid, page: page),
                              emptyText: 'TA 还没有回复过帖子',
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _header(ColorScheme scheme, String name) {
    final profile = _profile;
    final stats = <(String, String)>[
      ('主题', profile?.posts ?? ''),
      ('回复', profile?.replies ?? ''),
      ('金币', profile?.credits ?? ''),
      ('粉丝', profile?.followers ?? ''),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(url: profile?.avatar ?? '', name: name, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'MT论坛用户' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (profile?.group.isNotEmpty == true) _tag(scheme, profile!.group, scheme.primary),
                        if (profile?.level.isNotEmpty == true) _tag(scheme, profile!.level, scheme.tertiary),
                        _tag(scheme, 'UID ${widget.uid}', scheme.outline),
                      ],
                    ),
                    if (profile?.regTime.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        '注册于 ${profile!.regTime}',
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final stat in stats)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        stat.$2.isEmpty ? '—' : stat.$2,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(stat.$1, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _followBusy ? null : _toggleFollow,
                  icon: _followBusy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_following ? Icons.check_rounded : Icons.person_add_alt_1_rounded, size: 17),
                  label: Text(_following ? '已关注' : '关注'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openPm,
                  icon: const Icon(Icons.mail_outline_rounded, size: 17),
                  label: const Text('发消息'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(ColorScheme scheme, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );
}
