import 'package:flutter/material.dart';

import 'thread_glass.dart';

/// 玻璃胶囊的语义色：默认是中性玻璃，[accent] 用主色淡底，表示「已选中 /
/// 这是标签」这类需要被强调的对象。
enum GlassPillTone { neutral, accent }

/// 小玻璃胶囊：筛选条件、标签、联想词都用它。
///
/// 之前搜索页、标签页各写了一套：搜索页是白玻璃 + 主色选中态，标签页是
/// 主色淡底。同样是「一粒圆角小方块」，圆角一个 18 一个 20，按下有没有
/// 反馈也不一样。统一到这里，靠 [tone] 区分语义。
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.trailing,
    this.selected = false,
    this.tone = GlassPillTone.neutral,
    this.fontSize = 12.5,
    this.padding = const EdgeInsets.fromLTRB(12, 7, 12, 7),
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailing;
  final bool selected;
  final GlassPillTone tone;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = tone == GlassPillTone.accent;
    final fg = accent || selected ? scheme.primary : scheme.onSurfaceVariant;
    final fill = accent || selected
        ? scheme.primary.withValues(alpha: isDark ? 0.22 : 0.13)
        : Colors.white.withValues(alpha: isDark ? 0.09 : 0.44);
    final stroke = accent || selected
        ? scheme.primary.withValues(alpha: isDark ? 0.45 : 0.34)
        : ThreadGlass.borderColor(context);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: fill,
          border: Border.all(color: stroke, width: 0.9),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: padding,
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
        ),
      ),
    );
  }
}

/// 玻璃搜索框：不铺实心底色，只留一圈发丝描边和极淡的白色，
/// 让背后顶栏的模糊透上来。聚焦时描边转主色并带一圈微光。
///
/// 搜索页、浏览历史原来各写一套，一个圆角 23 一个 14、一个白玻璃一个实心灰。
class GlassSearchField extends StatefulWidget {
  const GlassSearchField({
    super.key,
    required this.controller,
    this.hintText = '搜索…',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.height = 46,
    this.leading = Icons.search_rounded,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final double height;
  final IconData leading;

  @override
  State<GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<GlassSearchField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused == _focus.hasFocus) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = scheme.primary.withValues(alpha: isDark ? 0.55 : 0.42);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.height / 2),
        color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.46),
        border: Border.all(
          color: _focused ? accent : ThreadGlass.borderColor(context),
          width: _focused ? 1.2 : 0.9,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18),
                  blurRadius: 14,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(widget.leading, size: 19, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              cursorHeight: 18,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
          ValueListenableBuilder(
            valueListenable: widget.controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 12)
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        widget.controller.clear();
                        widget.onChanged?.call('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.cancel_rounded,
                          size: 17,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 统一的圆角卡片：底色交给 [Material] 铺，水波纹才不会被外层容器挡住。
///
/// 之前关于页、MCP 页都把 `ListTile` 套在带底色的 `Container` 里，点击时
/// 水波纹画在更外层的 Material 上、被底色盖掉，点下去毫无反馈。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 18,
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: ThreadGlass.borderColor(context)),
    );
    return Material(
      color: color ?? Colors.white.withValues(alpha: isDark ? 0.08 : 0.44),
      clipBehavior: Clip.antiAlias,
      shape: shape,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}
