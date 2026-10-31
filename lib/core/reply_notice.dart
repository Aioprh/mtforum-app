/// 「回复某楼」时贴在正文最前面的引用条。
///
/// Discuz 的 `reppost` 参数只负责给对方发提醒：`post_newreply.php` 里那个分支
/// 从头到尾没动 `$message`，所以发出来的内容是一条看不出对象的独立回复——
/// 网页端也一样，只是界面上会显示「回复 xxx」的标签，客户端没有那层壳。
///
/// 这里自己补一条轻量引用：`[quote]` 会被渲染成灰色引用框，里面只有
/// 「回复 xxx 的帖子」，点名字能跳到被回复的楼层。不复制对方原文，
/// 那是「引用」按钮的活。
library;

String buildReplyNotice({
  required String author,
  required int pid,
  required int tid,
}) {
  final name = author.trim().isEmpty ? '该楼' : author.trim();
  return '[quote][size=2][color=#999999]回复 '
      '[url=forum.php?mod=redirect&goto=findpost&pid=$pid&ptid=$tid]'
      '$name[/url] 的帖子[/color][/size][/quote]';
}
