import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/navigation/swipe_navigation.dart';
import 'package:mt_forum/ui/navigation/text_selection_guard.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';

/// 长按选文本和「右拖后退」是同一个手势，选中期间手势导航要主动让路。
void main() {
  setUp(() {
    SwipeNavigator.instance.resetForTest();
    TextSelectionGuard.reset();
  });

  Widget app() => MaterialApp(
    navigatorKey: SwipeNavigator.instance.navigatorKey,
    navigatorObservers: [SwipeNavigator.instance],
    builder: (context, child) => SwipeGestureRegion(child: child!),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              appRoute(builder: (_) => const Scaffold(body: Center(child: Text('详情页')))),
            ),
            child: const Text('打开详情'),
          ),
        ),
      ),
    ),
  );

  Future<void> dragRight(WidgetTester tester, double fraction) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.timedDragFrom(
      Offset(20, size.height / 2),
      Offset(size.width * fraction, 0),
      const Duration(milliseconds: 1000),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('选中文本期间横拖不会退出页面', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情页'), findsOneWidget);

    TextSelectionGuard.setSelecting('test', true);
    await dragRight(tester, 0.5);
    // 这一趟是拉选，页面必须原地不动。
    expect(find.text('详情页'), findsOneWidget);

    TextSelectionGuard.setSelecting('test', false);
    await dragRight(tester, 0.5);
    // 取消选中之后手势恢复。
    expect(find.text('详情页'), findsNothing);
  });

  testWidgets('正文长按选中后会把状态报给手势层', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: PostHtmlView(html: '<p>这是一段可以被长按选中的正文，用来验证选择状态的上报。</p>'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(TextSelectionGuard.selecting, isFalse);

    await tester.longPress(find.textContaining('这是一段'));
    await tester.pumpAndSettle();

    expect(TextSelectionGuard.selecting, isTrue);
  });
}
