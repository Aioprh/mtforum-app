import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/block_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地屏蔽名单：用户匹配、关键词匹配、HTML 转纯文本。
void main() {
  final block = BlockList.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    block.debugReset();
    await block.load();
  });

  test('按用户名屏蔽，忽略大小写和首尾空格', () async {
    await block.blockUser('  Alice ');
    expect(block.blocksUser('alice'), isTrue);
    expect(block.blocksUser('ALICE', uid: 999), isTrue);
    expect(block.blocksUser('bob'), isFalse);
  });

  test('uid 优先于用户名：改名后仍能命中', () async {
    await block.blockUser('旧名字', uid: 42);
    expect(block.blocksUser('新名字', uid: 42), isTrue);
    expect(block.blocksUser('旧名字'), isTrue);
    expect(block.blocksUser('新名字', uid: 43), isFalse);
  });

  test('重复屏蔽不会产生第二条', () async {
    expect(await block.blockUser('张三'), isTrue);
    expect(await block.blockUser('张三'), isFalse);
    expect(block.users.length, 1);
  });

  test('解除屏蔽按 uid 或名字都行', () async {
    await block.blockUser('张三', uid: 7);
    await block.unblockUser(const BlockedUser(name: '张三', uid: 7));
    expect(block.blocksUser('张三', uid: 7), isFalse);
  });

  test('关键词命中任意一处', () async {
    await block.addKeyword('加群');
    await block.addKeyword('代下');
    expect(block.blocksText('想进群的加群 123'), isTrue);
    expect(block.blocksText('可以代下文件'), isTrue);
    expect(block.blocksText('正常回复'), isFalse);
  });

  test('英文关键词忽略大小写', () async {
    await block.addKeyword('AD');
    expect(block.blocksText('这是 ad 广告'), isTrue);
    expect(block.blocksText('没有命中'), isFalse);
  });

  test('重复关键词只留一条', () async {
    expect(await block.addKeyword('广告'), isTrue);
    expect(await block.addKeyword(' 广告 '), isFalse);
    expect(block.keywords.length, 1);
  });

  test('空关键词不命中任何文本', () async {
    await block.addKeyword('   ');
    expect(block.keywords, isEmpty);
    expect(block.blocksText('随便什么内容'), isFalse);
  });

  test('HTML 转纯文本后参与匹配', () async {
    await block.addKeyword('骗钱');
    const html = '<div>请<b>不要</b>骗钱<br>谢谢</div>';
    expect(block.blocksHtml(html), isTrue);
    expect(block.blocksHtml('<div>正常内容</div>'), isFalse);
  });

  test('HTML 实体与脚本不干扰匹配', () async {
    expect(BlockList.plainTextOf('<p>a&nbsp;b &amp; c</p>'), 'a b & c');
    expect(BlockList.plainTextOf('<script>alert(1)</script><p>正文</p>'), '正文');
    expect(BlockList.plainTextOf('<p>换行<br>下一行</p>'), '换行 下一行');
  });

  test('名单持久化到偏好，重载后还在', () async {
    await block.blockUser('李四', uid: 9);
    await block.addKeyword('外挂');
    block.debugReset();
    await block.load();
    expect(block.blocksUser('李四', uid: 9), isTrue);
    expect(block.blocksText('卖外挂'), isTrue);
  });
}
