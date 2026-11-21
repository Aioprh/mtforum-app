import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 私信正文的解析回归测试。
///
/// 网页版私信编辑器支持官方表情和 BBCode，服务端下发时已经转成
/// `<img src="…/smiley/…">`、`<b>`、`<blockquote>`。早先只取纯文本：
/// - 表情图标整段消失；
/// - 只发了一个表情的消息被判成空消息，直接从会话里消失。
void main() {
  final repo = ForumRepository.instance;

  const chatHtml = '''
<dl id="pmlist_801" class="bbda cl">
  <dd class="y mtm pm_o">
    <a href="javascript:;" id="pm_o_801" class="o">菜单</a>
    <div id="pm_o_801_menu" class="p_pop" style="display: none;">
      <ul><li><a href="javascript:;">删除</a></li></ul>
    </div>
  </dd>
  <dd class="m avt">
    <a href="home.php?mod=space&amp;uid=2002"><img src="uc_server/avatar.php?uid=2002"></a>
  </dd>
  <dd class="ptm">
    <a href="home.php?mod=space&amp;uid=2002" class="xw1">李四</a> &nbsp; <br />
    你好<b>加粗</b><img src="https://bbs.binmt.cc/static/image/smiley/qq/qq001.gif" border="0" alt="" /><a href="https://bbs.binmt.cc/thread-1-1-1.html">看这个帖子</a><br />
    <span class="xg1">2026-11-01 10:15</span>
  </dd>
</dl>
''';

  test('私信正文保留表情图片与行内标签', () {
    final (messages, _, peer) = repo.parsePmMessagesHtml(chatHtml, peerUid: 2002, myUid: 1);
    expect(messages.length, 1);
    final message = messages.single;
    expect(peer, '李四');
    expect(message.mine, isFalse);

    // 纯文本摘要里，表情还原成官方代码，不再凭空消失。
    expect(message.text, '你好加粗[呵呵]看这个帖子');
    expect(message.text.contains('2026'), isFalse);

    // HTML 版本交给气泡渲染，标签和图片都还在。
    expect(message.html, contains('<b>加粗</b>'));
    expect(message.html, contains('static/image/smiley/qq/qq001.gif'));
    expect(message.html, contains('thread-1-1-1.html'));
    expect(message.html.contains('xg1'), isFalse);
    expect(message.html.contains('菜单'), isFalse);
    // 尾部那个分隔用的 <br> 不能留：它会在气泡里多顶出一行空白。
    expect(message.html.endsWith('<br>'), isFalse);
  });

  test('只发一个表情的消息不会被当成空消息丢掉', () {
    const onlySmiley = '''
<dl id="pmlist_802" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=1"><img src="a.png"></a></dd>
  <dd class="ptm">
    <span class="xi2 xw1">您</span> &nbsp; <br />
    <img src="https://bbs.binmt.cc/static/image/smiley/qq/qq101.gif" border="0" alt="" /><br />
    <span class="xg1">2026-11-01 10:16</span>
  </dd>
</dl>
''';
    final (messages, _, _) = repo.parsePmMessagesHtml(onlySmiley, peerUid: 2002, myUid: 1);
    expect(messages.length, 1);
    expect(messages.single.text, '[抱拳]');
    expect(messages.single.html, contains('qq101.gif'));
    expect(messages.single.mine, isTrue);
  });

  test('引用与代码块原样交给气泡', () {
    const rich = '''
<dl id="pmlist_803" class="bbda cl">
  <dd class="m avt"><a href="home.php?mod=space&amp;uid=2002"><img src="a.png"></a></dd>
  <dd class="ptm">
    <a href="home.php?mod=space&amp;uid=2002" class="xw1">李四</a> &nbsp; <br />
    <blockquote>引用的一句话</blockquote><pre>if (a &lt; b) {}</pre>
  </dd>
</dl>
''';
    final (messages, _, _) = repo.parsePmMessagesHtml(rich, peerUid: 2002, myUid: 1);
    expect(messages.single.html, contains('<blockquote>'));
    expect(messages.single.html, contains('<pre>'));
    expect(messages.single.text, contains('引用的一句话'));
  });
}
