import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:mt_forum/core/code_block.dart';
import 'package:mt_forum/ui/widgets/code_block_card.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 帖子里的代码块要被认出来、按行取回原文，并且默认折叠。
///
/// 论坛手机模板把每一行代码渲染成一个 `<li>`，行号由 `<ol>` 生成。之前按
/// 普通 div 走，`<ol>` 被当成列表逐项渲染，长代码整屏铺开——这次两件事一起
/// 守住：源码按行提取，卡片默认只露 14 行。
void main() {
  String extract(String html) {
    final element = parser.parse(html).querySelector('.comiis_blockcode')!;
    return CodeBlock.extract(element);
  }

  group('源码提取', () {
    test('comiis 的 ol/li 结构按行拆开，不粘成一行', () {
      final code = extract('''
<div class="comiis_blockcode comiis_bodybg b_ok f_b"><div class="bg_f b_l"><ol><li>package com.oplus.appdetail;<br/>
</li><li><br/>
</li><li>import android.content.Intent;<br/>
</li></ol></div></div>
''');
      expect(code, 'package com.oplus.appdetail;\n\nimport android.content.Intent;');
    });

    test('保留缩进与行内空格，只去掉行尾空白', () {
      final code = extract('''
<div class="comiis_blockcode"><div><ol><li>&nbsp; &nbsp; return null;&nbsp;&nbsp;<br/>
</li></ol></div></div>
''');
      expect(code, '    return null;');
    });

    test('pre/code 结构保留原有换行', () {
      final code = extract('<div class="comiis_blockcode"><pre><code>line1\nline2\n</code></pre></div>');
      expect(code, 'line1\nline2');
    });

    test('首尾空行被去掉，内部空行保留', () {
      final code = extract('''
<div class="comiis_blockcode"><div><ol><li><br/>
</li><li>a<br/>
</li><li><br/>
</li><li>b<br/>
</li><li><br/>
</li></ol></div></div>
''');
      expect(code, 'a\n\nb');
    });
  });

  group('卡片渲染', () {
    Future<void> pump(WidgetTester tester, String html) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PostHtmlView(html: html))),
      ));
      await tester.pump();
    }

    String longCode(int lines) =>
        List.generate(lines, (i) => '  int value${i + 1} = ${i + 1};').join('<br/>\n');

    testWidgets('长代码默认折叠，只露前 14 行', (tester) async {
      await pump(tester, '''
<div class="comiis_blockcode"><div class="bg_f b_l"><ol><li>${longCode(20)}</li></ol></div></div>
''');

      expect(find.byType(CodeBlockCard), findsOneWidget);
      expect(find.textContaining('20 行'), findsOneWidget);
      expect(find.textContaining('展开全部 6 行'), findsOneWidget);
      expect(find.textContaining('value14', findRichText: true), findsOneWidget);
      expect(find.textContaining('value15', findRichText: true), findsNothing);
      // 行号列只排到折叠处，不该出现第 15 行之后的编号。
      expect(find.textContaining('收起代码'), findsNothing);
    });

    testWidgets('点开底部展开条后显示全部代码，可再收起', (tester) async {
      await pump(tester, '''
<div class="comiis_blockcode"><div class="bg_f b_l"><ol><li>${longCode(20)}</li></ol></div></div>
''');

      await tester.ensureVisible(find.textContaining('展开全部'));
      await tester.tap(find.textContaining('展开全部'));
      await tester.pump();

      expect(find.textContaining('value20', findRichText: true), findsOneWidget);
      expect(find.textContaining('收起代码'), findsOneWidget);
      expect(find.textContaining('已折叠'), findsNothing);

      await tester.ensureVisible(find.textContaining('收起代码'));
      await tester.tap(find.textContaining('收起代码'));
      await tester.pump();
      expect(find.textContaining('value20', findRichText: true), findsNothing);
    });

    testWidgets('短代码不显示展开条', (tester) async {
      await pump(tester, '''
<div class="comiis_blockcode"><div><ol><li>npm run build<br/>
</li><li>npm run test<br/>
</li></ol></div></div>
''');

      expect(find.byType(CodeBlockCard), findsOneWidget);
      expect(find.textContaining('2 行'), findsOneWidget);
      expect(find.textContaining('展开全部'), findsNothing);
      expect(find.textContaining('已折叠'), findsNothing);
    });

    testWidgets('代码块里的 ol 不会被渲染成有序列表', (tester) async {
      await pump(tester, '''
<div class="comiis_blockcode"><div><ol><li>first<br/>
</li><li>second<br/>
</li></ol></div></div>
''');

      // 列表标记是独立的 Text('1.')，代码块里不应该出现。
      expect(find.text('1.'), findsNothing);
      expect(find.textContaining('first', findRichText: true), findsOneWidget);
    });
  });
}
