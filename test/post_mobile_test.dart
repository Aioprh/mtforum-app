import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/http_session.dart';

/// Discuz 收到「POST + mobile」会先 302 到 `misc.php?mod=mobile`，
/// 写操作整个被丢掉。这里锁住「POST 前把 mobile 摘掉」这条规则。
void main() {
  test('POST 的 mobile 被摘掉，其余参数原样保留', () {
    final uri = Uri.parse(
      'https://bbs.binmt.cc/forum.php?mod=post&action=edit&fid=42&tid=176076&pid=12089521&editsubmit=yes&mobile=2',
    );
    final fixed = HttpSession.stripMobile(uri);
    expect(fixed.queryParameters.containsKey('mobile'), isFalse);
    expect(fixed.queryParameters['mod'], 'post');
    expect(fixed.queryParameters['action'], 'edit');
    expect(fixed.queryParameters['editsubmit'], 'yes');
    expect(fixed.queryParameters['pid'], '12089521');
  });

  test('没有 mobile 时原样返回', () {
    final uri = Uri.parse('https://bbs.binmt.cc/forum.php?mod=viewthread&tid=176076');
    expect(HttpSession.stripMobile(uri), same(uri));
  });

  test('只剩 mobile 一个参数时不会留下空问号', () {
    final uri = Uri.parse('https://bbs.binmt.cc/forum.php?mobile=2');
    final fixed = HttpSession.stripMobile(uri);
    expect(fixed.hasQuery, isFalse);
    expect(fixed.toString(), 'https://bbs.binmt.cc/forum.php');
  });

  test('fragment 与路径不被破坏', () {
    final uri = Uri.parse('https://bbs.binmt.cc/forum.php?mod=post&mobile=2#pid1');
    final fixed = HttpSession.stripMobile(uri);
    expect(fixed.fragment, 'pid1');
    expect(fixed.path, '/forum.php');
    expect(fixed.queryParameters['mod'], 'post');
  });
}
