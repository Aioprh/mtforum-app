import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 「本帖隐藏的内容」以前会跟着引用块一起被当纯文本渲染：一片灰字、链接
/// 点不了，长帖里一划就过去。现在单独认出来做成带色条的卡片，标题提上去，
/// 正文按普通段落渲染（可点链接、正常字色）。
void main() {
  Future<void> pumpHtml(WidgetTester tester, String html) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
    ));
    await tester.pump();
  }

  final card = find.byKey(const ValueKey('post-hidden-content'));

  bool hasLink(WidgetTester tester, String text) {
    var found = false;
    void walk(InlineSpan span) {
      if (found) return;
      if (span is TextSpan) {
        if (span.text == text && span.recognizer != null) {
          found = true;
          return;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child);
        }
      }
    }

    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      walk(rich.text);
      if (found) return true;
    }
    return false;
  }

  testWidgets('blockquote 外壳的隐藏内容做成卡片，标题只出现一次', (tester) async {
    await pumpHtml(tester, '''
      <blockquote class="blockquote">
        本帖隐藏的内容<br>
        <a href="https://1852353956.share.123pan.cn/123pan/UzfMvd-ywMuh">https://1852353956.share.123pan.cn/123pan/UzfMvd-ywMuh</a>
      </blockquote>
    ''');

    expect(card, findsOneWidget);
    expect(find.text('本帖隐藏的内容'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    // 链接仍然可点：藏起来的网盘地址是最需要点的那种。
    expect(hasLink(tester, 'https://1852353956.share.123pan.cn/123pan/UzfMvd-ywMuh'), isTrue);
  });

  testWidgets('div.quote 外壳、冒号结尾的写法同样认', (tester) async {
    await pumpHtml(tester, '''
      <div class="quote">本帖隐藏的内容：解压密码是 binmt2026</div>
    ''');

    expect(card, findsOneWidget);
    expect(find.text('本帖隐藏的内容'), findsOneWidget);
    expect(find.textContaining('解压密码是 binmt2026'), findsOneWidget);
  });

  testWidgets('普通段落里的这句话不算隐藏内容', (tester) async {
    // 教程帖里常拿这句话当小标题，套进卡片反而突兀。
    await pumpHtml(tester, '<p>本帖隐藏的内容：下面讲讲怎么提取安装包</p>');

    expect(card, findsNothing);
    expect(find.textContaining('下面讲讲怎么提取安装包'), findsOneWidget);
  });

  testWidgets('引用别人的楼层（带「发表于」）仍按引用渲染', (tester) async {
    await pumpHtml(tester, '''
      <blockquote class="blockquote">
        <font><a href="space-uid-34273.html">某某</a> 发表于 2026-10-28 10:00</font><br>
        本帖隐藏的内容：他说这里有链接
      </blockquote>
    ''');

    expect(card, findsNothing);
    expect(find.textContaining('发表于'), findsOneWidget);
  });
}
