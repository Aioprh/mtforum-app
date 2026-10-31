import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../pages/thread_page.dart';
import 'back_to_top.dart';
import 'state_views.dart';
import 'thread_card.dart';

/// 通用主题流：首屏加载、下拉刷新、触底加载更多。
class ThreadFeed extends StatefulWidget {
  const ThreadFeed({
    super.key,
    required this.loader,
    this.header,
    this.emptyText = '这里还没有内容',
    this.enabled = true,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 24),
    this.onRefresh,
    this.controller,
    this.doubleTapToTop = false,
  });

  final Future<List<ThreadSummary>> Function(int page) loader;
  final Widget? header;
  final String emptyText;
  final bool enabled;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;

  /// 外部传进来的滚动控制器，页面级的「双击顶栏回顶」要用。
  final ScrollController? controller;

  /// 内容区双击回到顶部。
  ///
  /// 只有滚离顶部之后才挂上双击识别，回到顶部就摘掉——否则单击进帖子
  /// 每次都要等双击判定超时，点起来会发钝。
  final bool doubleTapToTop;

  @override
  State<ThreadFeed> createState() => _ThreadFeedState();
}

class _ThreadFeedState extends State<ThreadFeed> {
  final List<ThreadSummary> _items = [];
  late final ScrollController _scroll;
  late final bool _ownsScroll;
  bool _loading = false;
  bool _initialized = false;
  bool _hasMore = true;
  bool _farFromTop = false;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scroll = widget.controller ?? ScrollController();
    _ownsScroll = widget.controller == null;
    _scroll.addListener(_onScroll);
    if (widget.enabled) _loadFirst();
  }

  @override
  void didUpdateWidget(covariant ThreadFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _loadFirst();
  }

  @override
  void dispose() {
    if (_ownsScroll) _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // 双击回顶只在离开首屏后启用，跨过阈值时刷新一次就够，别每帧都 setState。
    final far = _scroll.position.pixels > 8;
    if (far != _farFromTop) setState(() => _farFromTop = far);
    if (_loading || !_hasMore || _error != null) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = await widget.loader(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(batch);
        _page = 1;
        _hasMore = batch.length >= 10;
        _initialized = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _initialized = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final batch = await widget.loader(_page + 1);
      if (!mounted) return;
      setState(() {
        _page += 1;
        _items.addAll(batch);
        _hasMore = batch.length >= 10;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await widget.onRefresh?.call();
    _error = null;
    await _loadFirst();
  }

  String _message(Object error) => error is SiteException ? error.message : '加载失败，请稍后重试';

  Widget _skeletonCard(ColorScheme scheme) => Container(
        height: 132,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle)),
              const SizedBox(width: 9),
              Container(width: 78, height: 10, color: scheme.surfaceContainerHighest),
            ]),
            const SizedBox(height: 14),
            Container(height: 13, color: scheme.surfaceContainerHighest),
            const SizedBox(height: 8),
            FractionallySizedBox(widthFactor: 0.62, child: Container(height: 13, color: scheme.surfaceContainerHighest)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showSkeleton = _loading && _items.isEmpty && _error == null;

    final feed = RefreshIndicator(
      onRefresh: _refresh,
      edgeOffset: widget.header == null ? 0 : 8,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: widget.padding,
        itemCount: 1 + (showSkeleton ? 5 : _items.length) + 1,
        itemBuilder: (context, index) {
          if (index == 0) return widget.header ?? const SizedBox.shrink();

          if (showSkeleton) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _skeletonCard(scheme),
            );
          }

          final itemIndex = index - 1;
          if (itemIndex < _items.length) {
            final thread = _items[itemIndex];
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: ThreadCard(
                thread: thread,
                onDoubleTap: widget.doubleTapToTop && _farFromTop ? () => scrollToTop(_scroll) : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ThreadPage(tid: thread.tid, title: thread.title)),
                ),
              ),
            );
          }

          if (_items.isEmpty && _initialized && _error == null) {
            return SizedBox(
              height: 320,
              child: EmptyView(text: widget.emptyText),
            );
          }
          if (_error != null) {
            return ErrorView(
              message: _error!,
              compact: _items.isNotEmpty,
              onRetry: () {
                if (_items.isEmpty) {
                  _loadFirst();
                } else {
                  _loadMore();
                }
              },
            );
          }
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          if (!_hasMore && _items.isNotEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('— 已经到底啦 —', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
              ),
            );
          }
          return const SizedBox(height: 20);
        },
      ),
    );

    if (!widget.doubleTapToTop) return feed;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: _farFromTop ? () => scrollToTop(_scroll) : null,
      child: feed,
    );
  }
}
