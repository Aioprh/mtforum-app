import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mt_forum/data/forum_repository.dart';

/// 点赞回执与「是否已赞」的判定。
///
/// 线上问题是：赞成功却提示「点赞失败」，而且之后再点也取消不了——因为失败
/// 分支没有置位本地状态，下一次仍然发 add。这里把两个判据钉住。
void main() {
  group('点赞回执', () {
    test('站点没给文案也算成功', () {
      // 有的模板只回一段 script，CDATA 里没有中文，取出来是空串。
      expect(ForumRepository.recommendFailure(''), isNull);
    });

    test('各种成功文案都不能误判成失败', () {
      for (final message in <String>[
        '感谢您的参与，现在将转入主题页',
        '点赞成功',
        '操作成功',
        '评价成功',
        '取消成功',
        '已取消',
        '谢谢参与',
      ]) {
        expect(ForumRepository.recommendFailure(message), isNull, reason: message);
      }
    });

    test('已评价过要给出「已经赞过」而不是通用失败', () {
      expect(ForumRepository.recommendFailure('您已评价过本主题'), '你已经赞过这个帖子');
      expect(ForumRepository.recommendFailure('抱歉，您已经评价过'), '你已经赞过这个帖子');
      expect(ForumRepository.recommendFailure('您已经赞过该帖'), '你已经赞过这个帖子');
    });

    test('踩的重复提示用踩的措辞', () {
      expect(
        ForumRepository.recommendFailure('您已评价过本主题', up: false),
        '你已经踩过这个帖子',
      );
    });

    test('取消时服务端说没评价过，要能被识别', () {
      expect(ForumRepository.recommendFailure('您还没有评价过本主题'), '你还没有点赞');
    });

    test('其余明确失败仍然拦得住', () {
      expect(ForumRepository.recommendFailure('不能评价自己的帖子'), '不能点赞自己的帖子');
      expect(ForumRepository.recommendFailure('该主题已关闭'), '该主题已关闭，无法点赞');
      expect(ForumRepository.recommendFailure('今日评价机会已用完'), '今天的点赞次数已用完');
      expect(ForumRepository.recommendFailure('非法操作'), isNotNull);
      expect(ForumRepository.recommendFailure('您没有权限进行此操作'), isNotNull);
    });
  });

  group('从页面判断是否已赞', () {
    test('按钮带 f_a 激活类', () {
      final doc = html_parser.parse(
        '<a id="recommendv_add" class="comiis_recommend_a_color f_a">赞</a>',
      );
      expect(ForumRepository.threadLiked(doc), isTrue);
    });

    test('按钮已换成 do=cancel', () {
      final doc = html_parser.parse(
        '<a id="recommendv_add" '
        'href="forum.php?mod=misc&action=recommend&do=cancel&tid=1">取消</a>',
      );
      expect(ForumRepository.threadLiked(doc), isTrue);
    });

    test('未赞的页面', () {
      final doc = html_parser.parse(
        '<a id="recommendv_add" class="comiis_recommend_a_color" '
        'href="forum.php?mod=misc&action=recommend&do=add&tid=1">赞</a>',
      );
      expect(ForumRepository.threadLiked(doc), isFalse);
    });

    test('页面里没有点赞按钮（游客）', () {
      expect(ForumRepository.threadLiked(html_parser.parse('<div>请登录</div>')), isFalse);
    });
  });
}
