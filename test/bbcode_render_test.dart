import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/bbcode_render.dart';

/// 私信本地回显：刚发出去的那条还没经过服务端，得按官网同样的规则把
/// BBCode 转成 HTML，气泡才和对方看到的一致。
void main() {
  test('加粗、颜色、链接按官网格式转换', () {
    expect(bbcodeToHtml('[b]加粗[/b]'), '<b>加粗</b>');
    expect(
      bbcodeToHtml('[color=#ff0000]红字[/color]'),
      '<font color="#ff0000">红字</font>',
    );
    expect(
      bbcodeToHtml('[url=https://bbs.binmt.cc/thread-1-1-1.html]看帖[/url]'),
      '<a href="https://bbs.binmt.cc/thread-1-1-1.html">看帖</a>',
    );
    expect(
      bbcodeToHtml('[url]https://bbs.binmt.cc/[/url]'),
      '<a href="https://bbs.binmt.cc/">https://bbs.binmt.cc/</a>',
    );
  });

  test('官方表情代码转成表情图片', () {
    final html = bbcodeToHtml('你好[呵呵]');
    expect(html, contains('你好'));
    expect(html, contains('/static/image/smiley/qq/qq001.gif'));
    expect(html.contains('[呵呵]'), isFalse);
  });

  test('引用与代码块保留结构，代码里的 BBCode 不被二次解析', () {
    expect(bbcodeToHtml('[quote]引用[/quote]'), '<blockquote>引用</blockquote>');
    final code = bbcodeToHtml('[code][b]原样[/b][/code]');
    expect(code, '<pre>[b]原样[/b]</pre>');
  });

  test('换行转 <br>，普通尖括号按文字转义', () {
    expect(bbcodeToHtml('第一行\n第二行'), '第一行<br>第二行');
    final html = bbcodeToHtml('1 < 2 & 3 > 2');
    expect(html, contains('&lt;'));
    expect(html, contains('&gt;'));
    expect(html.contains('<2'), isFalse);
  });

  test('不是表情的中括号原样保留', () {
    expect(bbcodeToHtml('数组[0]和[测试]'), '数组[0]和[测试]');
  });
}
