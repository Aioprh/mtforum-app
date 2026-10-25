import 'package:flutter/material.dart';

/// 论坛发帖 / 回复可用的表情（Unicode，直接写入正文，服务端按 UTF-8 保存）。
const List<String> kForumEmojis = <String>[
  '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣',
  '😊', '😇', '🙂', '😉', '😍', '🥰', '😘', '😋',
  '😎', '🤓', '🧐', '🤔', '😐', '😑', '😶', '🙄',
  '😏', '😣', '😥', '😮', '🤯', '😳', '🥵', '🥶',
  '😱', '😨', '😰', '😢', '😭', '😤', '😡', '🤬',
  '👍', '👎', '👏', '🙏', '🤝', '💪', '👌', '✌️',
  '🤞', '👋', '🤙', '🫡', '🎉', '🎊', '🔥', '💯',
  '❤️', '💔', '💖', '⭐', '🌟', '✅', '❌', '⚠️',
  '🤖', '👻', '💩', '🐶', '🐱', '🍉', '☕', '🌹',
];

/// 在光标处插入文本；光标无效时追加到末尾。
void insertAtCursor(TextEditingController controller, String text) {
  final value = controller.value;
  final selection = value.selection;
  if (!selection.isValid || selection.start < 0 || selection.end < 0) {
    final next = '${value.text}$text';
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    return;
  }
  final start = selection.start;
  final end = selection.end;
  final next = value.text.replaceRange(start, end, text);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

/// 插入 BBCode 包裹，并把光标放在中间。
void insertWrapped(TextEditingController controller, String open, String close) {
  final value = controller.value;
  final selection = value.selection;
  final offset = selection.isValid ? selection.end : value.text.length;
  final inserted = '$open$close';
  final next = value.text.replaceRange(offset, offset, inserted);
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: offset + open.length),
  );
}

/// 表情面板：网格展示，点选后由调用方插入到输入框。
class EmojiPanel extends StatelessWidget {
  const EmojiPanel({super.key, required this.onSelected, this.height = 236});

  final ValueChanged<String> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: kForumEmojis.length,
        itemBuilder: (context, index) {
          final emoji = kForumEmojis[index];
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelected(emoji),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 23)),
            ),
          );
        },
      ),
    );
  }
}
