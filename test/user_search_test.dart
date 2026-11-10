import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 用户搜索结果解析。
///
/// 站点这套模板把「加好友 / 关注 / 发消息 / 打招呼」都塞在昵称上面，
/// 每个操作链接都带同一个 uid。解析必须以昵称链接为准，否则搜出来的人
/// 会变成「加好友」。
void main() {
  const row = '''
<div class="comiis_userlist01 cl">
  <li class="b_t">
    <p class="ytit f_d">
      <a href="https://bbs.binmt.cc/home.php?mod=spacecp&amp;ac=friend&amp;op=add&amp;uid=160721" class="dialog"><font>加好友</font></a>
      <a href="https://bbs.binmt.cc/home.php?mod=spacecp&amp;ac=follow&amp;op=add&amp;hash=abc&amp;fuid=160721" class="dialog"><font>关注</font></a>
      <a href="https://bbs.binmt.cc/home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=160721"><font>发消息</font></a>
    </p>
    <a href="https://bbs.binmt.cc/home.php?mod=space&amp;uid=160721&amp;do=profile" class="list01_limg bg_e">
      <img src="https://cdn.binmt.cc/uc_server/data/avatar/000/16/07/21_avatar_middle.jpg?v=x" />
    </a>
    <p class="tit"><a href="https://bbs.binmt.cc/home.php?mod=space&amp;uid=160721&amp;do=profile">卡哇伊</a></p>
    <p class="txt f_d">
      <font style="margin-right:3px;">高中生</font>
      积分: 1523
    </p>
  </li>
</div>
''';

  test('解析昵称、uid、头像、用户组与积分', () {
    final hits = ForumRepository.parseUserHitsForTest(row);
    expect(hits, hasLength(1));
    final user = hits.single;
    expect(user.uid, 160721);
    expect(user.username, '卡哇伊');
    expect(user.avatar, contains('avatar_middle.jpg'));
    expect(user.group, '高中生');
    expect(user.credits, '1523');
  });

  test('操作按钮上的 uid 不会把昵称顶掉', () {
    final hits = ForumRepository.parseUserHitsForTest(row);
    expect(hits.single.username, isNot(contains('加好友')));
    expect(hits.single.username, isNot(contains('关注')));
  });

  test('同一个人出现多行只保留一条', () {
    final hits = ForumRepository.parseUserHitsForTest('$row$row');
    expect(hits, hasLength(1));
  });

  test('没有积分时整段作为用户组', () {
    const html = '''
<div class="comiis_userlist01">
  <li>
    <p class="tit"><a href="https://bbs.binmt.cc/home.php?mod=space&uid=7&do=profile">小明</a></p>
    <p class="txt f_d">版主</p>
  </li>
</div>
''';
    final hits = ForumRepository.parseUserHitsForTest(html);
    expect(hits.single.group, '版主');
    expect(hits.single.credits, isEmpty);
  });

  test('多个用户的顺序与页面一致', () {
    const html = '''
<div class="comiis_userlist01">
  <li>
    <p class="tit"><a href="https://bbs.binmt.cc/home.php?mod=space&uid=11&do=profile">甲</a></p>
    <p class="txt">高中生 积分: 10</p>
  </li>
  <li>
    <p class="tit"><a href="https://bbs.binmt.cc/home.php?mod=space&uid=12&do=profile">乙</a></p>
    <p class="txt">硕士生 积分: 20</p>
  </li>
</div>
''';
    final hits = ForumRepository.parseUserHitsForTest(html);
    expect(hits.map((e) => e.username), ['甲', '乙']);
    expect(hits.map((e) => e.uid), [11, 12]);
  });

  test('空页面和没有昵称的行都返回空', () {
    expect(ForumRepository.parseUserHitsForTest(''), isEmpty);
    expect(
      ForumRepository.parseUserHitsForTest(
        '<div class="comiis_userlist01"><li><p class="tit"></p></li></div>',
      ),
      isEmpty,
    );
  });
}
