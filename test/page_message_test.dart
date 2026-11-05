import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/page_message.dart';

/// 编辑页的「本帖最后由 … 编辑」记录和真正的错误提示共用 `.alert_info`，
/// 早先保存修改后会被当成错误，导致停在编辑页不回帖子。
void main() {
  test('识别编辑记录', () {
    const text = '本帖最后由 Aiopr·皇者 于 2026-10-31 17:32 编辑 '
        '更新内容：增加签到状态显示，修复部分bug 只要登录了每天打开一次软件就会自动签到';
    expect(isEditNote(text), isTrue);
  });

  test('前面有空白也算', () {
    expect(isEditNote('  本帖最后由 某人 于 2026-01-01 10:00 编辑'), isTrue);
  });

  test('真正的提示不被误杀', () {
    expect(isEditNote('抱歉，您的帖子小于 10 个字符的限制'), isFalse);
    expect(isEditNote('编辑帖子成功'), isFalse);
    expect(isEditNote(''), isFalse);
  });

  group('剔掉编辑记录', () {
    test('纯文本：月份不补零也要吃掉', () {
      const text = '本帖最后由 Aiopr·皇者 于 2026-11-6 01:00 编辑\n\n【非MT官方】\n\n更新日志：补全大部分功能';
      final cleaned = stripEditNote(text);
      expect(cleaned.startsWith('【非MT官方】'), isTrue);
      expect(cleaned.contains('本帖最后由'), isFalse);
    });

    test('纯文本：补零、斜杠日期、行首有空格', () {
      for (final stamp in [
        '本帖最后由 某人 于 2026-11-06 01:00 编辑',
        '本帖最后由 某人 于 2026/11/6 01:00 编辑',
        '  本帖最后由 某人 于 2026-11-6 01:00 编辑',
      ]) {
        final cleaned = stripEditNote('$stamp\n正文第一行');
        expect(cleaned, '正文第一行');
      }
    });

    test('HTML：pstatus 与 comiis_edit 两种容器', () {
      const html = '<i class="pstatus"> 本帖最后由 JiGuro 于 2026-6-20 23:47 编辑 </i><br/>'
          '<div class="comiis_edit">本帖最后由 A 于 2026-10-29 14:36 编辑</div>'
          '<div>正文内容</div>';
      final cleaned = stripEditNote(html);
      expect(cleaned.contains('本帖最后由'), isFalse);
      expect(cleaned.contains('正文内容'), isTrue);
    });

    test('正文里恰好写到「编辑」二字不误删整段', () {
      const text = '这个帖子我要编辑一下，晚点补充\n正文';
      expect(stripEditNote(text), text);
    });
  });
}
