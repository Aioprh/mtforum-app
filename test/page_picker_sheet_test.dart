import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/thread_paging.dart';
import 'package:mt_forum/ui/widgets/page_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 页码选择浮层。
///
/// 起因：翻页条中间只有一行「第 N 页」死文字，几十页的帖子只能一页页点
/// 「下一页」，每点一次还要等一次请求。把它做成入口，点开就能选任意页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 打开浮层，返回一个可读的容器——选中的页码在浮层关闭之后才写进去。
  Future<List<int?>> open(
    WidgetTester tester, {
    required int current,
    required int total,
  }) async {
    final picked = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked.add(await PagePickerSheet.show(context, current: current, total: total));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('打开后列出页码，并标出总页数', (tester) async {
    await open(tester, current: 1, total: 12);

    expect(find.text('跳转到页码'), findsOneWidget);
    expect(find.text('共 12 页'), findsOneWidget);
    expect(find.text('12'), findsOneWidget, reason: '最后一页也要能点');
  });

  testWidgets('点页码直接回传，浮层关掉', (tester) async {
    final picked = await open(tester, current: 1, total: 12);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(picked, [3]);
    expect(find.text('跳转到页码'), findsNothing);
  });

  testWidgets('输入超出总页数的页码时拦下来，不关浮层', (tester) async {
    final picked = await open(tester, current: 1, total: 12);

    await tester.enterText(find.byType(TextField), '99');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();

    expect(find.text('这帖只有 12 页'), findsOneWidget);
    expect(picked, isEmpty);
    expect(find.text('跳转到页码'), findsOneWidget);
  });

  testWidgets('输入合法页码后跳转', (tester) async {
    final picked = await open(tester, current: 1, total: 12);

    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.text('跳转'));
    await tester.pumpAndSettle();

    expect(picked, [9]);
  });

  testWidgets('总页数未知时只列到当前页附近，标题退化成当前页', (tester) async {
    await open(tester, current: 5, total: 0);

    expect(find.text('第 5 页'), findsOneWidget);
    expect(find.textContaining('共 '), findsNothing);
  });

  group('总页数折算', () {
    test('分页控件给了最大页码就用它', () {
      expect(
        ThreadPaging.totalPages(fromLinks: 9, labeled: 0, total: 0, totalKnown: false),
        9,
      );
    });

    test('分页控件只显示当前页附近时，用第 1 页楼数补尾巴', () {
      // 93 楼 → 10 页；控件被折叠成到第 4 页，不能只列 4 页。
      expect(
        ThreadPaging.totalPages(fromLinks: 4, labeled: 0, total: 93, totalKnown: true),
        10,
      );
    });

    test('「共 N 页」文案也采信', () {
      expect(
        ThreadPaging.totalPages(fromLinks: 0, labeled: 7, total: 0, totalKnown: false),
        7,
      );
    });

    test('什么信号都没有时至少一页', () {
      expect(
        ThreadPaging.totalPages(fromLinks: 0, labeled: 0, total: 0, totalKnown: false),
        1,
      );
    });

    test('第 2 页以后的本页条数不能拿来算总页数', () {
      // 第 2 页只剩 6 条，totalKnown=false 时不该算出 1 页。
      expect(
        ThreadPaging.totalPages(fromLinks: 3, labeled: 0, total: 6, totalKnown: false),
        3,
      );
    });
  });
}
