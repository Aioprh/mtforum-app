import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../pages/thread_page.dart';
import '../widgets/thread_feed.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenSearch});

  final VoidCallback? onOpenSearch;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const List<(String, String, IconData)> _views = [
    ('最新', 'newthread', Icons.bolt_rounded),
    ('回复', 'new', Icons.chat_bubble_outline_rounded),
    ('热门', 'newreply', Icons.local_fire_department_rounded),
    ('精华', 'digest', Icons.workspace_premium_rounded),
  ];

  int _selected = 0;
  List<ThreadSummary> _announcements = const [];

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements({bool force = false}) async {
    try {
      final list = await AppState.instance.announcements(force: force);
      if (!mounted) return;
      setState(() => _announcements = list);
    } catch (_) {
      // 公告加载失败不影响主列表。
    }
  }

  Future<List<ThreadSummary>> _loader(int page) =>
      AppState.instance.repo.fetchGuide(_views[_selected].$2, page: page);

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.primary.withValues(alpha: 0.72)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.forum_rounded, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MT论坛', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                    const SizedBox(height: 1),
                    Text(
                      'MT管理器官方社区',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: widget.onOpenSearch,
                icon: const Icon(Icons.search_rounded, size: 21),
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surface,
                  foregroundColor: scheme.onSurface,
                  minimumSize: const Size(42, 42),
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
              ),
            ],
          ),
        ),
        if (_announcements.isNotEmpty) ...[
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _announcements.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final item = _announcements[index];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ThreadPage(tid: item.tid, title: item.title)),
                  ),
                  child: Container(
                    width: 262,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.075),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
                          child: Icon(Icons.campaign_rounded, size: 17, color: scheme.primary),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.8, height: 1.4, fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              Text(
                                item.time.isEmpty ? '官方公告' : '官方公告 · ${item.time}',
                                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < _views.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _selected == i ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _views[i].$3,
                            size: 15,
                            color: _selected == i ? Colors.white : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _views[i].$1,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: _selected == i ? FontWeight.w700 : FontWeight.w600,
                              color: _selected == i ? Colors.white : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ThreadFeed(
          key: ValueKey(_views[_selected].$2),
          loader: _loader,
          header: _header(context),
          onRefresh: () => _loadAnnouncements(force: true),
          emptyText: '暂时没有内容，稍后再来看看',
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 88),
        ),
      ),
    );
  }
}
