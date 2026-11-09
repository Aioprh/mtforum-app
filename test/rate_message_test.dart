import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 打赏提交后的提示解析。
///
/// 站点在成功响应里只放「返回本帖」的地址（有的模板连一句「评分成功」都
/// 不写），照着引号内容弹出来就是一串 https://…。这类地址不是文案，要当成
/// 「没给提示」处理，让上层补默认的「打赏成功」。
void main() {
  String wrap(String inner) =>
      '<?xml version="1.0" encoding="utf-8"?>\n<root><![CDATA[$inner]]></root>';

  group('打赏提示', () {
    test('提示位只有回跳地址时返回空，由调用方补「打赏成功」', () {
      final body = wrap(
        "<script type=\"text/javascript\" reload=\"1\">"
        "succeedhandle_rate('https://bbs.binmt.cc/forum.php?mod=viewthread&tid=176295&pid=123456&mobile=2')"
        '</script>',
      );
      expect(ForumRepository.rateMessage(body), isEmpty);
    });

    test('相对地址同样不算文案', () {
      final body = wrap(
        "<script>succeedhandle_rate('forum.php?mod=viewthread&tid=176295&mobile=2')</script>",
      );
      expect(ForumRepository.rateMessage(body), isEmpty);
    });

    test('正常成功文案原样返回', () {
      final body = wrap(
        "<script>succeedhandle_rate('您的评分已成功，谢谢参与!')</script>",
      );
      expect(ForumRepository.rateMessage(body), '您的评分已成功，谢谢参与!');
    });

    test('文案里夹着地址时只保留文字', () {
      final body = wrap(
        "<script>succeedhandle_rate('打赏成功 https://bbs.binmt.cc/forum.php?mod=viewthread&tid=1')</script>",
      );
      expect(ForumRepository.rateMessage(body), '打赏成功');
    });

    test('地址指向登录页说明登录态失效，不能当成功', () {
      final body = wrap(
        "<script>succeedhandle_rate('https://bbs.binmt.cc/member.php?mod=logging&action=login&mobile=2')</script>",
      );
      expect(ForumRepository.rateMessage(body), contains('重新登录'));
    });

    test('错误文案仍要原样带回，上层据此提示失败', () {
      final body = wrap(
        "<script>errorhandle_rate('抱歉，24 小时评分数超过限制')</script>",
      );
      expect(ForumRepository.rateMessage(body), contains('24 小时评分数超过限制'));
    });

    test('非 ajax 的整页响应里只取正文提示', () {
      const body = '<html><body><div class="comiis_message_table">'
          '您的评分已成功，谢谢参与!'
          '<a href="https://bbs.binmt.cc/forum.php?mod=viewthread&tid=1">'
          'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=1</a>'
          '</div></body></html>';
      expect(ForumRepository.rateMessage(body), '您的评分已成功，谢谢参与!');
    });

    test('整页响应只有跳转链接时也不弹网址', () {
      const body = '<html><body><div class="comiis_message_table">'
          '<a href="https://bbs.binmt.cc/forum.php?mod=viewthread&tid=1">'
          'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=1</a>'
          '</div></body></html>';
      expect(ForumRepository.rateMessage(body), isEmpty);
    });
  });
}
