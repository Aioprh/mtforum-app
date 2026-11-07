import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 拉黑状态识别。
///
/// Comiis 手机模板没有「我的黑名单」页入口，主页上「拉黑ta」点过之后会把
/// 按钮换成「解除拉黑」，链接形如：
/// `home.php?mod=spacecp&ac=friend&op=blacklist&subop=delete&uid=160721&start=`
/// 这里只认这个链接，不额外请求黑名单列表。
void main() {
  String page(String href, {String label = '解除拉黑'}) =>
      '<div class="comiis_userlist01"><ul class="flexbox">'
      '<li class="flex"><a href="$href" class="dialog"><span class="f_wb">$label</span></a></li>'
      '</ul></div>';

  test('主页给出「解除拉黑」链接时算已拉黑', () {
    final html = page(
      'https://bbs.binmt.cc/home.php?mod=spacecp&ac=friend&op=blacklist'
      '&subop=delete&uid=160721&start=&mobile=2',
    );
    expect(ForumRepository.hasBlockedLink(html, 160721), isTrue);
  });

  test('&amp; 编码的链接同样认', () {
    final html = page(
      'https://bbs.binmt.cc/home.php?mod=spacecp&amp;ac=friend&amp;op=blacklist'
      '&amp;subop=delete&amp;uid=160721&amp;start=',
    );
    expect(ForumRepository.hasBlockedLink(html, 160721), isTrue);
  });

  test('未拉黑时页面只有「拉黑ta」按钮，不算已拉黑', () {
    final html = '<li class="flex"><a href="javascript:popup.open(\'是否加入黑名单?\', '
        '\'confirm\', \'javascript:comiis_adduserblacklist();\');">'
        '<span class="f_b">拉黑ta</span></a></li>'
        '<script>function comiis_adduserblacklist(){'
        'url:"./home.php?mod=spacecp&ac=friend&op=blacklist&start=&inajax=1",'
        'data:"blacklistsubmit=true&formhash=617d2811&username=卡哇伊"}</script>';
    expect(ForumRepository.hasBlockedLink(html, 160721), isFalse);
  });

  test('uid 前缀相同不会误判', () {
    final html = page(
      'https://bbs.binmt.cc/home.php?mod=spacecp&ac=friend&op=blacklist'
      '&subop=delete&uid=16072&start=',
    );
    expect(ForumRepository.hasBlockedLink(html, 160721), isFalse);
    expect(ForumRepository.hasBlockedLink(html, 16072), isTrue);
  });

  test('黑名单列表页里的那条链接也能认出来', () {
    final html = page(
      'https://bbs.binmt.cc/home.php?mod=spacecp&ac=friend&op=blacklist'
      '&subop=delete&uid=160721&start=',
    );
    expect(ForumRepository.hasBlockedLink(html, 160721), isTrue);
  });

  test('空页面与非法 uid 直接判否', () {
    expect(ForumRepository.hasBlockedLink('', 160721), isFalse);
    expect(ForumRepository.hasBlockedLink(page('uid=1'), 0), isFalse);
  });
}
