import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../pages/thread_page.dart';
import 'back_to_top.dart';
import 'state_views.dart';
import 'thread_card.dart';
import '../navigation/swipe_navigation.dart';

/// 通用主题流：首屏加载、下拉刷新、触底加载更多。
class ThreadFeed extends StatefulWidget {
  const ThreadFeed({
    super.key,
    required this.loader,
    this.header,
    this.pinnedHeader,
    this.pinnedHeaderHeight = 56,
    this.emptyText = '这里还没有内容',
    this.enabled = true,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 14, 24),
    this.onRefresh,
    this.controller,
    this.doubleTapToTop = false,
  });

  final Future<List<ThreadSummary>> Function(int page) loader;
  final Widget? header;

  /// 会吸顶的横条：随列表上滑，滚到顶部后钉住不再消失。
  ///
  /// 和 [header] 的区别在于它单独占一个 sliver，滚动到顶端后贴在屏幕上方，
  /// 适合放「最新 / 热门 / 精华」这类需要随时切换的筛选条。
  final Widget? pinnedHeader;

  /// 吸顶条的高度。SliverPersistentHeader 需要提前知道占位高度，
  /// 所以这里必须是个固定值。
  final double pinnedHeaderHeight;

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

  /// 列表尾部的状态：空、出错、加载中、到底。
  Widget _tail(ColorScheme scheme, bool showSkeleton) {
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
        child: Center(
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showSkeleton = _loading && _items.isEmpty && _error == null;

    // header 与吸顶条各自占一个 sliver，列表项放进 SliverPadding，
    // 这样吸顶条能独立钉在顶部，不会跟着帖子一起滚走。
    final slivers = <Widget>[
      if (widget.header != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.padding.left,
              widget.padding.top,
              widget.padding.right,
              0,
            ),
            child: widget.header,
          ),
        ),
      if (widget.pinnedHeader != null)
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeaderDelegate(
            height: widget.pinnedHeaderHeight,
            background: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: EdgeInsets.only(
                left: widget.padding.left,
                right: widget.padding.right,
              ),
              child: widget.pinnedHeader,
            ),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          widget.padding.left,
          0,
          widget.padding.right,
          widget.padding.bottom,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (showSkeleton) {
                if (index < 5) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _skeletonCard(scheme),
                  );
                }
                return _tail(scheme, showSkeleton);
              }

              if (index < _items.length) {
                final thread = _items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: ThreadCard(
                    thread: thread,
                    onDoubleTap:
                        widget.doubleTapToTop && _farFromTop ? () => scrollToTop(_scroll) : null,
                    onTap: () => Navigator.of(context).push(
                      appRoute(builder: (_) => ThreadPage(tid: thread.tid, title: thread.title)),
                    ),
                  ),
                );
              }
              return _tail(scheme, showSkeleton);
            },
            childCount: (showSkeleton ? 5 : _items.length) + 1,
          ),
        ),
      ),
    ];

    final feed = RefreshIndicator(
      onRefresh: _refresh,
      edgeOffset: widget.header == null ? 0 : 8,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: slivers,
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

/// 固定高度的吸顶条。
///
/// 用 OverflowBox 把内容按自然高度居中，超出部分裁掉——系统字体放大时
/// 筛选条不会报 RenderFlex overflow，只是上下各裁掉一点。
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedHeaderDelegate({
    required this.height,
    required this.background,
    required this.child,
  });

  final double height;
  final Color background;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRect(
      child: ColoredBox(
        color: background,
        child: OverflowBox(
          alignment: Alignment.center,
          minHeight: 0,
          maxHeight: 200,
          child: child,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.background != background ||
      oldDelegate.child != child;
}
