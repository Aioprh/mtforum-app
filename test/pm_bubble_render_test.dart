import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 私信气泡里的正文排版：比帖子正文小一号，且能跟随气泡底色。
void main() {
  Future<void> render(WidgetTester tester, {Color? color}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          child: PostHtmlView(
            html: '好的<img src="https://bbs.binmt.cc/static/image/smiley/qq/qq001.gif">收到',
            dense: true,
            selectable: false,
            textColor: color,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('私信正文用紧凑字号，表情仍留在段落里', (tester) async {
    await render(tester);

    final paragraph = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((widget) => widget.text.toPlainText().contains('好的'));
    expect(paragraph.text.style?.fontSize, 13.5);
    expect(paragraph.text.style?.height, 1.45);

    final stack = <InlineSpan>[paragraph.text];
    var hasSmiley = false;
    while (stack.isNotEmpty) {
      final span = stack.removeLast();
      if (span is WidgetSpan) hasSmiley = true;
      if (span is TextSpan) stack.addAll(span.children ?? const <InlineSpan>[]);
    }
    expect(hasSmiley, isTrue, reason: '表情应当作为行内图片保留');
  });

  testWidgets('气泡底色是主色时正文用 onPrimary', (tester) async {
    const color = Color(0xFFFFFFFF);
    await render(tester, color: color);

    final paragraph = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((widget) => widget.text.toPlainText().contains('好的'));
    expect(paragraph.text.style?.color, color);
  });

  testWidgets('表情图片加载失败时不抛出页面异常', (tester) async {
    await render(tester);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}
