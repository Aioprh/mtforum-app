import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import 'internal_browser_page.dart';
import 'pm_list_page.dart';

/// 消息通知：回复提醒、@提醒与系统通知。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Future<void> _openCategory(String title, String url) async {
    if (title == '我的消息') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PmListPage()));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InternalBrowserPage(url: AppConfig.uri(url).toString(), title: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const categories = <({String title, String subtitle, IconData icon, Color color, String url})>[
      (title: '我的消息', subtitle: '私信与会话', icon: Icons.chat_bubble_rounded, color: Color(0xFF55B8E8), url: 'home.php?mod=space&do=pm'),
      (title: '我的粉丝', subtitle: '关注我的坛友', icon: Icons.groups_rounded, color: Color(0xFFE97D8A), url: 'home.php?mod=follow&do=follower'),
      (title: '我的帖子', subtitle: '回复、评论与 @ 提醒', icon: Icons.forum_rounded, color: Color(0xFF9BC20D), url: 'home.php?mod=space&do=notice&view=interactive'),
      (title: '坛友互动', subtitle: '好友与关注互动', icon: Icons.send_rounded, color: Color(0xFFF5B400), url: 'home.php?mod=space&do=notice&view=friend'),
      (title: '系统提醒', subtitle: '系统通知与管理提醒', icon: Icons.notifications_active_rounded, color: Color(0xFFE97D8A), url: 'home.php?mod=space&do=notice&view=system'),
      (title: '应用提醒', subtitle: '应用相关通知', icon: Icons.sensors_rounded, color: Color(0xFF8BB5E4), url: 'home.php?mod=space&do=notice&view=app'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('消息提醒')),
      body: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: categories.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.45)),
        itemBuilder: (context, index) {
          final item = categories[index];
          return ListTile(
            minVerticalPadding: 16,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
              child: Icon(item.icon, color: Colors.white, size: 25),
            ),
            title: Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            subtitle: Text(item.subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.outline),
            onTap: () => _openCategory(item.title, item.url),
          );
        },
      ),
    );
  }

}
