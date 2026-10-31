import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/reply_notice.dart';

/// 回复某楼时贴在正文前的引用条。Discuz 的 reppost 只发提醒、不改正文，
/// 所以「回复 xxx」这层信息得客户端自己带上。
void main() {
  test('带上作者、pid 与 tid', () {
    final notice = buildReplyNotice(author: 'Aioprh', pid: 12345, tid: 678);
    expect(notice, startsWith('[quote]'));
    expect(notice, endsWith('[/quote]'));
    expect(notice, contains('回复 '));
    expect(notice, contains('Aioprh'));
    expect(notice, contains('pid=12345'));
    expect(notice, contains('ptid=678'));
  });

  test('作者为空时不留空白', () {
    final notice = buildReplyNotice(author: '  ', pid: 1, tid: 2);
    expect(notice, contains('该楼'));
    expect(notice, isNot(contains('  ')));
  });

  test('不复制对方原文', () {
    final notice = buildReplyNotice(author: '某人', pid: 9, tid: 3);
    // 只有一层 quote，没有第二段正文。
    expect('[/quote]'.allMatches(notice).length, 1);
  });
}
