import 'package:flutter/material.dart';

import 'glass_controls.dart';
import 'thread_glass.dart';

/// 页码选择浮层：把「第 N 页」变成可点的入口，直接跳到任意一页。
///
/// 原来只有「上一页 / 下一页」两个胶囊，几十页的帖子要从第 1 页翻到第 30 页
/// 得点二十九次，每点一次还要等一次请求。这里给一个整页网格，常用的近处
/// 页码直接点，远处的用底部输入框写数字。
class PagePickerSheet extends StatefulWidget {
  const PagePickerSheet({
    super.key,
    required this.current,
    required this.total,
  });

  /// 当前所在页。
  final int current;

  /// 已知总页数；0 表示站点没给出，只列到「当前页 + 若干页」。
  final int total;

  static Future<int?> show(
    BuildContext context, {
    required int current,
    required int total,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.26),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PagePickerSheet(current: current, total: total),
    );
  }

  @override
  State<PagePickerSheet> createState() => _PagePickerSheetState();
}

class _PagePickerSheetState extends State<PagePickerSheet> {
  static const int _columns = 6;
  static const double _rowExtent = 42;
  static const double _gap = 8;

  late final TextEditingController _input;
  late final ScrollController _scroll;
  String? _error;

  /// 总页数未知时列到第几页：当前页往后留两屏，够点着试。
  int get _lastPage {
    if (widget.total > 0) {
      return widget.total < widget.current ? widget.current : widget.total;
    }
    return widget.current + 12;
  }

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: '${widget.current}');
    _scroll = ScrollController();
    // 打开时让当前页那一行落在可视区中上部，长帖不用自己滚半天找。
    // 偏移要等网格量出 maxScrollExtent 才能 clamp，否则末尾几页会被顶到最底。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final row = (widget.current - 1) ~/ _columns;
      final target = row * (_rowExtent + _gap) - 96;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(int page, {bool typed = false}) {
    if (page < 1) {
      setState(() => _error = '页码从 1 开始');
      return;
    }
    final max = _lastPage;
    // 总页数未知时，网格只列到附近几页；手输则放行，用户多半知道自己在找第几页，
    // 站点对越界页也只是把最后一页再发一遍，不会报错。
    if (page > max && !(typed && widget.total <= 0)) {
      setState(() => _error = widget.total > 0 ? '这帖只有 $max 页' : '页码超出已知范围');
      return;
    }
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    final rows = (_lastPage + _columns - 1) ~/ _columns;
    final gridHeight = rows * (_rowExtent + _gap);
    // 标题行 + 抓手 + 底部输入行大约占这么多，剩下的才是网格能用的高度。
    final maxGridHeight = maxHeight - 190;
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
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
              child: Row(
                children: [
                  const Text(
                    '跳转到页码',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.total > 0
                        ? '共 ${widget.total} 页'
                        : '第 ${widget.current} 页',
                    style: TextStyle(fontSize: 11.5, color: scheme.outline),
                  ),
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
            SizedBox(
              // 页数少时网格只有内容那么高，面板跟着收；页数多了才顶到上限滚动。
              height: gridHeight < maxGridHeight ? gridHeight : maxGridHeight,
              child: GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  mainAxisExtent: _rowExtent,
                  crossAxisSpacing: _gap,
                  mainAxisSpacing: _gap,
                ),
                itemCount: _lastPage,
                itemBuilder: (context, index) {
                  final page = index + 1;
                  return _PageCell(
                    page: page,
                    current: page == widget.current,
                    onTap: () => _jumpTo(page),
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                6,
                18,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GlassField(
                          controller: _input,
                          hintText: '输入页码',
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (value) => _jumpTo(
                            int.tryParse(value.trim()) ?? 0,
                            typed: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      SizedBox(
                        height: 46,
                        child: FilledButton(
                          onPressed: () => _jumpTo(
                            int.tryParse(_input.text.trim()) ?? 0,
                            typed: true,
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            '跳转',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _error!,
                          style: TextStyle(fontSize: 10.5, color: scheme.error),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一个页码格子：当前页用主色实底，其余是淡玻璃底。
class _PageCell extends StatelessWidget {
  const _PageCell({
    required this.page,
    required this.current,
    required this.onTap,
  });

  final int page;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    final fg = current ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: current
              ? scheme.primary
              : ThreadGlass.fill(context, lightAlpha: 0.44, darkAlpha: 0.09),
          border: Border.all(
            color: current ? scheme.primary : ThreadGlass.borderColor(context),
            width: 0.9,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Center(
            child: Text(
              '$page',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
