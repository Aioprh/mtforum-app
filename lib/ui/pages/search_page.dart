import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/thread_card.dart';
import 'login_page.dart';
import 'thread_page.dart';

/// 站内搜索（Discuz 原生搜索流程）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialKeyword = ''});

  final String initialKeyword;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with AutomaticKeepAliveClientMixin {
  static const List<String> _suggestions = ['MT管理器', '教程', '求助', '逆向', '修改'];

  late final TextEditingController _keyword = TextEditingController(text: widget.initialKeyword);

  List<ForumCategory> _categories = const [];
  List<ThreadSummary> _results = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextPage = 11;
  bool _searched = false;
  String? _error;
  int _fid = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadBoards();
    if (widget.initialKeyword.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _loadBoards() async {
    try {
      final value = await AppState.instance.boards();
      if (!mounted) return;
      setState(() => _categories = value);
    } catch (_) {
      // 版块筛选加载失败不影响搜索。
    }
  }

  Future<void> _search() async {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty) {
      _toast('请输入搜索关键词');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
      _results = const [];
    });
    try {
      const batchPages = 10;
      final items = await AppState.instance.repo.search(keyword, fid: _fid, page: 1, maxPages: batchPages);
      if (!mounted) return;
      setState(() {
        _results = items;
        _nextPage = batchPages + 1;
        _hasMore = items.length >= batchPages * 10;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is SiteException ? e.message : '搜索失败，请稍后重试';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final keyword = _keyword.text.trim();
    setState(() => _loadingMore = true);
    try {
      const batchPages = 10;
      final items = await AppState.instance.repo.search(
        keyword,
        fid: _fid,
        page: _nextPage,
        maxPages: batchPages,
      );
      if (!mounted) return;
      final seen = _results.map((item) => item.tid).toSet();
      final fresh = items.where((item) => seen.add(item.tid)).toList();
      setState(() {
        _results = [..._results, ...fresh];
        _nextPage += batchPages;
        _hasMore = items.length >= batchPages * 10;
        _loadingMore = false;
      });
      if (fresh.isEmpty && items.isNotEmpty) {
        _toast('本页结果与已显示帖子重复，可继续加载后续结果');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(e is SiteException ? e.message : '加载更多失败，请重试');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) _search();
  }

  List<(String, int)> get _boardOptions {
    final options = <(String, int)>[('全部版块', 0)];
    for (final category in _categories) {
      for (final board in category.boards) {
        options.add(('${category.name} / ${board.name}', board.fid));
      }
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keyword,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: '搜索帖子、教程或资源…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 21),
                        suffixIcon: ValueListenableBuilder(
                          valueListenable: _keyword,
                          builder: (context, value, _) => value.text.isEmpty
                              ? const SizedBox.shrink()
                              : IconButton(
                                  onPressed: () => setState(() => _keyword.clear()),
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _search,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(52, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search_rounded, size: 22),
                    ),
                  ),
                ],
              ),
            ),
            if (_categories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: DropdownButtonFormField<int>(
                  initialValue: _fid,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    prefixIcon: Icon(Icons.tune_rounded, size: 18),
                  ),
                  items: [
                    for (final option in _boardOptions)
                      DropdownMenuItem(value: option.$2, child: Text(option.$1, style: const TextStyle(fontSize: 13))),
                  ],
                  onChanged: (value) => setState(() => _fid = value ?? 0),
                ),
              ),
            Expanded(child: _resultArea(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _resultArea(ColorScheme scheme) {
    if (!_searched) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
        children: [
          Icon(Icons.travel_explore_rounded, size: 54, color: scheme.outline.withValues(alpha: 0.55)),
          const SizedBox(height: 14),
          Text(
            '输入关键词，找到你需要的帖子',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in _suggestions)
                ActionChip(
                  label: Text(word, style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                  backgroundColor: scheme.surfaceContainerHighest,
                  side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
                  onPressed: () {
                    _keyword.text = word;
                    _search();
                  },
                ),
            ],
          ),
        ],
      );
    }
    if (_loading) {
      return const FeedSkeleton(count: 4);
    }
    if (_error != null) {
      final needLogin = _error!.contains('登录');
      return ListView(
        padding: const EdgeInsets.only(top: 40),
        children: [
          ErrorView(message: _error!, onRetry: _search),
          if (needLogin)
            Center(
              child: OutlinedButton.icon(
                onPressed: _openLogin,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('去登录'),
              ),
            ),
        ],
      );
    }
    if (_results.isEmpty) {
      return const EmptyView(text: '没有找到相关帖子，换个关键词试试', icon: Icons.search_off_rounded);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      itemCount: _results.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 11),
      itemBuilder: (context, index) {
        if (index == _results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Text('已显示 ${_results.length} 条结果', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                if (_hasMore) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loadingMore ? null : _loadMore,
                    icon: _loadingMore
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text(_loadingMore ? '正在加载…' : '加载更多帖子'),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('没有更多结果了', style: TextStyle(fontSize: 11, color: scheme.outline)),
                  ),
              ],
            ),
          );
        }
        final thread = _results[index];
        return ThreadCard(
          thread: thread,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ThreadPage(tid: thread.tid, title: thread.title)),
          ),
        );
      },
    );
  }
}
