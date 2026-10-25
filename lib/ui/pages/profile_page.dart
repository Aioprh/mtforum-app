import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/thread_feed.dart';
import '../widgets/user_avatar.dart';
import 'about_page.dart';
import 'login_page.dart';
import 'notifications_page.dart';
import 'rankings_page.dart';
import 'tags_page.dart';

/// 个人中心：账号信息、我的主题 / 回复 / 收藏、外观与退出。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (AppState.instance.isLoggedIn && AppState.instance.profile == null) {
      AppState.instance.refreshProfile();
    }
  }

  Future<void> _refresh() async {
    if (!AppState.instance.isLoggedIn) return;
    await AppState.instance.refreshProfile(silent: false);
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录成功')));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后将无法发帖、回复与收藏，确定要退出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppState.instance.logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出登录')));
  }

  Future<void> _pickTheme() async {
    final current = AppState.instance.themeMode;
    final options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, '跟随系统', Icons.brightness_auto_rounded),
      (ThemeMode.light, '浅色模式', Icons.light_mode_rounded),
      (ThemeMode.dark, '深色模式', Icons.dark_mode_rounded),
    ];
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text('主题外观', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final option in options)
              ListTile(
                leading: Icon(option.$3),
                title: Text(option.$2),
                trailing: current == option.$1 ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, option.$1),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (mode != null) await AppState.instance.setThemeMode(mode);
  }

  void _openPersonal(String title, String path, Map<String, String> query, String emptyText) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PersonalThreadsPage(title: title, path: path, query: query, emptyText: emptyText),
    ));
  }

  void _openPage(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _signIn() async {
    if (!AppState.instance.isLoggedIn) {
      await _openLogin();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await AppState.instance.repo.signIn();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is SiteException ? e.message : '签到失败，请稍后重试')));
    }
  }

  Future<void> _openSiteMenu() async {
    final entries = <(String, String, Map<String, String>, IconData)>[
      ('道具中心', 'home.php', {'mod': 'magic', 'mobile': '2'}, Icons.auto_fix_high_outlined),
      ('勋章中心', 'home.php', {'mod': 'medal', 'mobile': '2'}, Icons.military_tech_outlined),
      ('任务中心', 'home.php', {'mod': 'task', 'mobile': '2'}, Icons.task_alt_rounded),
      ('积分', 'home.php', {'mod': 'spacecp', 'ac': 'credit', 'mobile': '2'}, Icons.toll_outlined),
      ('积分商城', 'plugin.php', {'id': 'k_mall:index', 'mobile': '2'}, Icons.storefront_outlined),
      ('访问推广', 'home.php', {'mod': 'spacecp', 'ac': 'promotion', 'mobile': '2'}, Icons.campaign_outlined),
    ];
    final index = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('更多站点功能', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            for (var i = 0; i < entries.length; i++)
              ListTile(
                leading: Icon(entries[i].$4, size: 21),
                title: Text(entries[i].$1, style: const TextStyle(fontSize: 14)),
                trailing: const Icon(Icons.open_in_browser_rounded, size: 17),
                onTap: () => Navigator.pop(sheetContext, i),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (index == null) return;
    final entry = entries[index];
    await launchUrl(AppConfig.uri(entry.$2, entry.$3), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) {
        final state = AppState.instance;
        final profile = state.profile;
        return Scaffold(
          appBar: AppBar(
            title: const Text('我的'),
            actions: [
              if (state.isLoggedIn)
                IconButton(
                  tooltip: '刷新资料',
                  onPressed: state.profileLoading ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
              children: [
                if (state.isLoggedIn) ...[
                  _profileHeader(scheme, profile, state.profileLoading),
                  const SizedBox(height: 18),
                  _menuGroup(scheme, [
                    _MenuItem(Icons.article_outlined, '我的主题', () {
                      _openPersonal('我的主题', 'home.php', {
                        'mod': 'space',
                        'do': 'thread',
                        'mobile': '2',
                      }, '你还没有发布过主题');
                    }),
                    _MenuItem(Icons.chat_bubble_outline_rounded, '我的回复', () {
                      _openPersonal('我的回复', 'home.php', {
                        'mod': 'space',
                        'do': 'reply',
                        'mobile': '2',
                      }, '你还没有回复过帖子');
                    }),
                    _MenuItem(Icons.star_outline_rounded, '我的收藏', () {
                      _openPersonal('我的收藏', 'home.php', {
                        'mod': 'space',
                        'do': 'favorite',
                        'view': 'me',
                        'mobile': '2',
                      }, '你还没有收藏帖子');
                    }),
                  ]),
                  const SizedBox(height: 14),
                  _menuGroup(scheme, [
                    _MenuItem(Icons.notifications_none_rounded, '消息通知', () {
                      _openPage(const NotificationsPage());
                    }),
                    _MenuItem(Icons.event_available_outlined, '每日签到', _signIn),
                  ]),
                  const SizedBox(height: 14),
                ] else ...[
                  _loginCard(scheme),
                  const SizedBox(height: 18),
                ],
                _menuGroup(scheme, [
                  _MenuItem(Icons.leaderboard_outlined, '排行榜', () {
                    _openPage(const RankingsPage());
                  }),
                  _MenuItem(Icons.sell_outlined, '标签', () {
                    _openPage(const TagsPage());
                  }),
                  _MenuItem(Icons.apps_rounded, '更多站点功能', _openSiteMenu),
                ]),
                const SizedBox(height: 14),
                _menuGroup(scheme, [
                  _MenuItem(Icons.palette_outlined, '主题外观', _pickTheme),
                  _MenuItem(Icons.info_outline_rounded, '关于本应用', () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage()));
                  }),
                ]),
                if (state.isLoggedIn) ...[
                  const SizedBox(height: 14),
                  _menuGroup(scheme, [
                    _MenuItem(Icons.logout_rounded, '退出登录', _logout, danger: true),
                  ]),
                ],
                const SizedBox(height: 26),
                Text(
                  'MT论坛 · ${state.isLoggedIn ? '已登录' : '未登录'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _loginCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_rounded, size: 30, color: scheme.primary),
          ),
          const SizedBox(height: 12),
          const Text('登录 MT论坛账号', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            '发帖、回复、收藏与查看个人主页',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }

  Widget _profileHeader(ColorScheme scheme, UserProfile? profile, bool loading) {
    final stats = <(String, String)>[
      ('主题', profile?.posts ?? ''),
      ('回复', profile?.replies ?? ''),
      ('金币', profile?.credits ?? ''),
      ('粉丝', profile?.followers ?? ''),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(url: profile?.avatar ?? '', name: profile?.username ?? '', size: 58),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.username.isNotEmpty == true ? profile!.username : 'MT论坛用户',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (profile?.group.isNotEmpty == true) _tag(scheme, profile!.group, scheme.primary),
                        if (profile?.level.isNotEmpty == true) _tag(scheme, profile!.level, scheme.tertiary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (profile != null && profile.uid > 0) 'UID ${profile.uid}',
                        if (profile?.regTime.isNotEmpty == true) '注册于 ${profile!.regTime}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final stat in stats)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        stat.$2.isEmpty ? '—' : stat.$2,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(stat.$1, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(ColorScheme scheme, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
        child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _menuGroup(ColorScheme scheme, List<_MenuItem> items) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
            ListTile(
              leading: Icon(items[i].icon, size: 21, color: items[i].danger ? scheme.error : scheme.onSurfaceVariant),
              title: Text(
                items[i].label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: items[i].danger ? scheme.error : scheme.onSurface,
                ),
              ),
              trailing: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.outline),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.label, this.onTap, {this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
}

/// 个人主题 / 回复 / 收藏列表。
class _PersonalThreadsPage extends StatelessWidget {
  const _PersonalThreadsPage({
    required this.title,
    required this.path,
    required this.query,
    required this.emptyText,
  });

  final String title;
  final String path;
  final Map<String, String> query;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        top: false,
        child: ThreadFeed(
          loader: (page) => AppState.instance.repo.fetchPersonalList(
            path,
            query: {...query, 'page': '$page'},
          ),
          emptyText: emptyText,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        ),
      ),
    );
  }
}
