import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/glass_app_bar.dart';
import '../widgets/measure_height.dart';
import '../widgets/state_views.dart';
import '../widgets/thread_glass.dart';
import '../widgets/thread_card.dart';
import 'login_page.dart';
import 'thread_page.dart';
import '../navigation/app_routes.dart';

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

  /// 输入框聚焦时给玻璃边缘加一圈主色，让人知道现在能打字。
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  List<ForumCategory> _categories = const [];
  List<ThreadSummary> _results = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextPage = 11;
  bool _searched = false;
  String? _error;
  int _fid = 0;

  /// 顶部玻璃搜索条的实测高度，首帧给个估值（一行输入框 66）。
  double _barHeight = 66;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
    _loadBoards();
    if (widget.initialKeyword.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _keyword.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
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

  void _onFocusChanged() {
    if (_focused == _focus.hasFocus) return;
    setState(() => _focused = _focus.hasFocus);
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      noSwipeRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) _search();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final topInset = glassTopInset(context);
    // 结果列表的顶部留白要跟搜索条实际高度对齐，否则第一张卡片会被压在
    // 玻璃条下面。高度由 MeasureHeight 量，首帧先给个估值。
    return Scaffold(
      // 结果列表从玻璃顶栏和搜索条背后滚过。
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('搜索')),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(child: _resultArea(scheme, topInset + _barHeight)),
            Positioned(
              top: topInset,
              left: 0,
              right: 0,
              child: MeasureHeight(
                onHeight: _onBarMeasured,
                child: GlassBackdrop(
                  showBorder: false,
                  opacityScale: 0.94,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: ThreadGlass.borderColor(context), width: 0.6),
                      ),
                    ),
                    child: _searchBar(scheme),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onBarMeasured(double height) {
    if ((height - _barHeight).abs() < 0.5) return;
    setState(() => _barHeight = height);
  }

  Widget _searchBar(ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _searchField(scheme, isDark)),
              const SizedBox(width: 9),
              _SearchBead(loading: _loading, onTap: _loading ? null : _search),
            ],
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 9),
            _GlassPill(
              label: _filterLabel,
              icon: Icons.tune_rounded,
              trailing: Icons.keyboard_arrow_down_rounded,
              selected: _fid != 0,
              onTap: _openBoardPicker,
            ),
          ],
        ],
      ),
    );
  }

  /// 输入框自己就是一粒玻璃：不铺底色，只留一圈发丝描边和极淡的填充，
  /// 让背后顶栏的模糊透上来，和底栏、回复框是同一块玻璃。
  Widget _searchField(ColorScheme scheme, bool isDark) {
    final accent = scheme.primary.withValues(alpha: isDark ? 0.55 : 0.42);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.46),
        border: Border.all(color: _focused ? accent : ThreadGlass.borderColor(context), width: _focused ? 1.2 : 0.9),
        boxShadow: _focused
            ? [BoxShadow(color: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18), blurRadius: 14, spreadRadius: 0.5)]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, size: 19, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _keyword,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              cursorHeight: 18,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: '搜索帖子、教程或资源…',
                hintStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant.withValues(alpha: 0.72)),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: _keyword,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 12)
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _keyword.clear()),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.cancel_rounded, size: 17, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String get _filterLabel {
    if (_fid == 0) return '全部版块';
    for (final category in _categories) {
      for (final board in category.boards) {
        if (board.fid == _fid) return board.name;
      }
    }
    return '全部版块';
  }

  /// 版块筛选改成玻璃浮层：一屏能把所有版块按分区看清，
  /// 比原来那个铺满全屏的灰菜单轻得多。
  Future<void> _openBoardPicker() async {
    if (_categories.isEmpty) {
      _toast('版块列表还没加载好，稍后再试');
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BoardPickerSheet(categories: _categories, selected: _fid),
    );
    if (!mounted || picked == null || picked == _fid) return;
    setState(() => _fid = picked);
    if (_searched && _keyword.text.trim().isNotEmpty) _search();
  }

  Widget _resultArea(ColorScheme scheme, double topPadding) {
    // 悬浮玻璃底栏浮在页面之上（Scaffold.extendBody），列表末尾要多留一段，
    // 否则最后一条结果被压在底栏下面。88 与首页、版块页保持一致。
    final bottomPad = 26 + floatingNavSpace(context);

    if (!_searched) {
      return ListView(
        padding: EdgeInsets.fromLTRB(20, topPadding + 26, 20, bottomPad),
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
                _GlassPill(
                  label: word,
                  onTap: () {
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
      return Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: const FeedSkeleton(count: 4),
      );
    }
    if (_error != null) {
      final needLogin = _error!.contains('登录');
      return ListView(
        padding: EdgeInsets.only(top: topPadding + 40),
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
      return Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: const EmptyView(text: '没有找到相关帖子，换个关键词试试', icon: Icons.search_off_rounded),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(14, topPadding + 4, 14, bottomPad),
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
            appRoute(builder: (_) => ThreadPage(tid: thread.tid, title: thread.title)),
          ),
        );
      },
    );
  }
}

/// 搜索按钮：一粒带主色渐变的玻璃珠，按下时轻微收缩。
class _SearchBead extends StatefulWidget {
  const _SearchBead({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  State<_SearchBead> createState() => _SearchBeadState();
}

class _SearchBeadState extends State<_SearchBead> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.62,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(scheme.primary, Colors.white, 0.22)!,
                  scheme.primary,
                  Color.lerp(scheme.primary, Colors.black, 0.12)!,
                ],
                stops: const [0, 0.55, 1],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.20 : 0.52), width: 1),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: isDark ? 0.34 : 0.26),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Center(
              child: widget.loading
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                    )
                  : Icon(Icons.search_rounded, size: 21, color: scheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// 小玻璃胶囊：筛选、联想词都用它，选中态换成主色淡底。
class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.selected = false,
    this.fontSize = 12.5,
    this.padding = const EdgeInsets.fromLTRB(12, 7, 12, 7),
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailing;
  final bool selected;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? scheme.primary : scheme.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.13)
              : Colors.white.withValues(alpha: isDark ? 0.09 : 0.44),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: isDark ? 0.45 : 0.34)
                : ThreadGlass.borderColor(context),
            width: 0.9,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 2),
              Icon(trailing, size: 16, color: fg.withValues(alpha: 0.8)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 版块筛选浮层：按分区列出全部版块，选中即回传 fid。
///
/// 原来的下拉菜单一展开就是一张铺满屏幕的灰板，十几个版块挤成
/// 「分区 / 版块」长字符串，既看不清也选不准。
class BoardPickerSheet extends StatelessWidget {
  const BoardPickerSheet({super.key, required this.categories, required this.selected});

  final List<ForumCategory> categories;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: GlassBackdrop(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        opacityScale: 1.06,
        showShadow: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 9),
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 2),
              child: Row(
                children: [
                  Text('选择版块', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Text('${categories.fold<int>(0, (sum, e) => sum + e.boards.length)} 个', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            Flexible(
              // shrinkWrap + loose：版块少的时候浮层只有内容那么高，
              // 多了才顶到 68% 的上限，不会留一大块空玻璃。
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
                children: [
                  _AllBoardsTile(selected: selected == 0, onTap: () => Navigator.of(context).pop(0)),
                  for (final category in categories) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 9),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 12,
                            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(width: 7),
                          Text(category.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 6),
                          Text('${category.boards.length}', style: TextStyle(fontSize: 10.5, color: scheme.outline)),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final board in category.boards)
                          _GlassPill(
                            label: board.name,
                            selected: board.fid == selected,
                            fontSize: 13,
                            padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                            onTap: () => Navigator.of(context).pop(board.fid),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllBoardsTile extends StatelessWidget {
  const _AllBoardsTile({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected ? scheme.primary : scheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.13)
              : Colors.white.withValues(alpha: isDark ? 0.09 : 0.44),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: isDark ? 0.45 : 0.34)
                : ThreadGlass.borderColor(context),
            width: 0.9,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.apps_rounded, size: 18, color: fg),
            const SizedBox(width: 10),
            Text('全部版块', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
            const Spacer(),
            if (selected) Icon(Icons.check_rounded, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
