import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 引用块必须收进灰色摘要卡片，而不是和本楼正文混成一段。
void main() {
  Future<void> pump(WidgetTester tester, String html) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
    ));
    await tester.pump();
  }

  testWidgets('div.quote 渲染成引用卡片，头部不是链接', (tester) async {
    await pump(tester, '''
<div class="quote"><font size="2"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=1&amp;ptid=2"><font color="#999999">Cynnue 发表于 9 分钟前</font></a></font><br />
话说这个布局一些图标怎么跟我之前开源的这么像</div>
<p>布局是让 ai 搞的，软件那么多相似点不很正常么</p>
''');

    final head = tester.widget<Text>(find.text('Cynnue 发表于 9 分钟前'));
    expect(head.maxLines, 1);
    expect(head.style?.decoration, isNot(TextDecoration.underline));

    final body = tester.widget<Text>(find.text('话说这个布局一些图标怎么跟我之前开源的这么像'));
    expect(body.maxLines, 3);
    expect(body.style?.decoration, isNot(TextDecoration.underline));

    expect(find.text('布局是让 ai 搞的，软件那么多相似点不很正常么'), findsOneWidget);
  });

  testWidgets('标准 blockquote 与 div.quote 表现一致', (tester) async {
    await pump(tester, '''
<blockquote><font size="2"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=1&amp;ptid=2"><font color="#999999">回复 网暴真的太可怕了 发表于 2026-10-29 00:57</font></a></font><br />
你居然放弃了她？她删除你的时候一定哭了。</blockquote>
<p>我把视频私发你自己看吧</p>
''');

    expect(tester.widget<Text>(find.text('回复 网暴真的太可怕了 发表于 2026-10-29 00:57')).maxLines, 1);
    expect(tester.widget<Text>(find.text('你居然放弃了她？她删除你的时候一定哭了。')).maxLines, 3);
  });

  testWidgets('引用正文保留分段，并且不重复渲染原图', (tester) async {
    await pump(tester, '''
<div class="quote"><font size="2"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;pid=1&amp;ptid=2">老张 发表于 2026-10-29 08:00</a></font><br />
第一段<br />
第二段<img src="https://img.example.com/a.jpg" /></div>
<p>收到</p>
''');

    expect(find.text('第一段\n第二段'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('没有引用的楼层仍是普通段落', (tester) async {
    await pump(tester, '<p>纯正文，没有任何引用</p>');
    expect(find.text('纯正文，没有任何引用'), findsOneWidget);
    expect(find.byType(GestureDetector), findsNothing);
  });
}
