import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/pages/search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索页的两个维度：帖子 / 用户。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('顶部有帖子与用户两个切换项', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.pump();

    expect(find.text('帖子'), findsOneWidget);
    expect(find.text('用户'), findsOneWidget);
    // 默认是帖子模式，引导文案属于帖子。
    expect(find.text('输入关键词，找到你需要的帖子'), findsOneWidget);
  });

  testWidgets('切到用户模式会换成用户引导，切回帖子恢复正常', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.pump();

    await tester.tap(find.text('用户'));
    await tester.pump();
    expect(find.text('输入用户名，找到 TA 的主页和帖子'), findsOneWidget);
    expect(find.text('输入关键词，找到你需要的帖子'), findsNothing);

    await tester.tap(find.text('帖子'));
    await tester.pump();
    expect(find.text('输入关键词，找到你需要的帖子'), findsOneWidget);
  });

  testWidgets('用户模式不显示版块筛选', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.pump();

    await tester.tap(find.text('用户'));
    await tester.pump();
    expect(find.text('全部版块'), findsNothing);
  });
}
