import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_highlight.dart';

/// 帖子里的代码块卡片。
///
/// 论坛的教程帖经常贴几十上百行反编译产物，整块铺在正文里会把一屏撑成
/// 三屏，往下翻很久都看不到下一段说明。这里默认只露前面十几行，剩下的
/// 折起来，想看完点一下底部那行「展开全部」即可。
class CodeBlockCard extends StatefulWidget {
  const CodeBlockCard({
    super.key,
    required this.code,
    required this.language,
    this.collapsedLines = 14,
  });

  final String code;
  final CodeLanguage language;

  /// 折叠时露出的行数。14 行大约一屏的三分之一，够看出这段在干什么。
  final int collapsedLines;

  @override
  State<CodeBlockCard> createState() => _CodeBlockCardState();
}

class _CodeBlockCardState extends State<CodeBlockCard> {
  bool _expanded = false;

  static const Color _background = Color(0xFF1D232B);
  static const Color _backgroundDark = Color(0xFF0B0E13);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = scheme.brightness == Brightness.dark
        ? _backgroundDark
        : _background;
    final lines = widget.code.split('\n');
    final total = lines.length;
    final foldable = total > widget.collapsedLines;
    final shown = foldable && !_expanded
        ? lines.take(widget.collapsedLines).join('\n')
        : widget.code;
    final shownCount = foldable && !_expanded ? widget.collapsedLines : total;
    final textScaler = MediaQuery.textScalerOf(context);
    // 等宽字体 12.5 号，一个数字大约 7.6 宽；再加 4 的余量，别贴边。
    final gutterWidth =
        (4 + 7.6 * '$total'.length) * (textScaler.scale(12.5) / 12.5);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 0),
            child: Row(
              children: [
                Text(
                  '${widget.language.label} · $total 行',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (foldable && !_expanded) ...[
                  const SizedBox(width: 6),
                  const Text(
                    '已折叠',
                    style: TextStyle(color: Colors.white30, fontSize: 10.5),
                  ),
                ],
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.code));
                    ScaffoldMessenger.maybeOf(context)
                        ?.showSnackBar(const SnackBar(content: Text('代码已复制')));
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(44, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('复制', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: gutterWidth,
                  child: Text(
                    CodeHighlight.lineNumbers(shownCount),
                    textAlign: TextAlign.right,
                    style: CodeHighlight.codeStyle.copyWith(
                      color: CodeHighlight.gutterColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // 用 Text.rich 而不是裸 RichText：后者不参与外层的
                    // SelectionArea，正文能长按选，代码块却选不了。
                    child: Text.rich(
                      CodeHighlight.span(shown, widget.language),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (foldable)
            _FoldBar(
              expanded: _expanded,
              hiddenLines: total - widget.collapsedLines,
              color: background,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
        ],
      ),
    );
  }
}

/// 卡片底部那条「展开 / 收起」。
///
/// 折叠时上面压一层渐变，让被切断的最后一行自然淡出，不至于像渲染坏了。
class _FoldBar extends StatelessWidget {
  const _FoldBar({
    required this.expanded,
    required this.hiddenLines,
    required this.color,
    required this.onTap,
  });

  final bool expanded;
  final int hiddenLines;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!expanded)
            IgnorePointer(
              child: Container(
                height: 26,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0), color],
                  ),
                ),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  expanded ? '收起代码' : '展开全部 $hiddenLines 行',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: Colors.white60,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
