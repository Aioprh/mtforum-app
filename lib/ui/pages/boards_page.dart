import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../pages/board_threads_page.dart';
import '../widgets/back_to_top.dart';
import '../widgets/smart_image.dart';
import '../widgets/state_views.dart';

class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key});

  @override
  State<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends State<BoardsPage> with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();
  List<ForumCategory> _categories = const [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final value = await AppState.instance.boards(force: force);
      if (!mounted) return;
      setState(() {
        _categories = value;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('版块'),
        // 顶栏空白处双击回顶。
        flexibleSpace: DoubleTapTopArea(controller: _scroll),
        actions: [
          IconButton(
            onPressed: () => _load(force: true),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新版块',
          ),
        ],
      ),
      body: _loading && _categories.isEmpty
          ? const FeedSkeleton(count: 4)
          : _error != null && _categories.isEmpty
              ? ErrorView(message: _error!, onRetry: () => _load(force: true))
              : RefreshIndicator(
                  onRefresh: () => _load(force: true),
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 88),
                    itemCount: _categories.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _categories.length) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
                          child: Text(
                            '共 ${_categories.fold<int>(0, (sum, e) => sum + e.boards.length)} 个版块',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: scheme.outline),
                          ),
                        );
                      }
                      final category = _categories[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 2, 4, 9),
                              child: Row(
                                children: [
                                  Container(width: 4, height: 14, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2))),
                                  const SizedBox(width: 8),
                                  Text(category.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                                  const SizedBox(width: 8),
                                  Text('${category.boards.length}', style: TextStyle(fontSize: 11, color: scheme.outline)),
                                ],
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 9,
                                crossAxisSpacing: 9,
                                mainAxisExtent: 70,
                              ),
                              itemCount: category.boards.length,
                              itemBuilder: (context, i) => _BoardTile(board: category.boards[i]),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({required this.board});

  final ForumBoard board;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BoardThreadsPage(fid: board.fid, name: board.name)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              board.icon.isEmpty
                  ? Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
                      child: Icon(Icons.forum_outlined, size: 19, color: scheme.primary),
                    )
                  : SmartImage(url: board.icon, width: 38, height: 38, radius: BorderRadius.circular(11), fit: BoxFit.contain),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      board.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      board.todayPosts > 0 ? '今日 ${board.todayPosts}' : '进入版块',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: board.todayPosts > 0 ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: board.todayPosts > 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
