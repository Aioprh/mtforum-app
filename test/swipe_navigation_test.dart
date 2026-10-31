import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/navigation/swipe_navigation.dart';

/// 手势导航：右拖后退、左拖前进、阈值与回弹。
void main() {
  setUp(() => SwipeNavigator.instance.resetForTest());

  Widget app({Widget? home}) => MaterialApp(
    navigatorKey: SwipeNavigator.instance.navigatorKey,
    navigatorObservers: [SwipeNavigator.instance],
    builder: (context, child) => SwipeGestureRegion(child: child!),
    home: home ?? const _HomePage(),
  );

  Future<void> openDetail(WidgetTester tester) async {
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情页'), findsOneWidget);
  }

  Future<void> dragRight(WidgetTester tester, double fraction, {bool fast = false}) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final delta = Offset(size.width * fraction, 0);
    if (fast) {
      await tester.flingFrom(Offset(20, size.height / 2), delta, 1600);
    } else {
      // 慢速拖动：1 秒走完，速度低于快速滑动阈值，只按距离判定。
      await tester.timedDragFrom(
        Offset(20, size.height / 2),
        delta,
        const Duration(milliseconds: 1000),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> dragLeft(WidgetTester tester, double fraction) async {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.timedDragFrom(
      Offset(size.width - 20, size.height / 2),
      Offset(-size.width * fraction, 0),
      const Duration(milliseconds: 1000),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('右拖超过 30% 屏幕宽度：退出当前页面', (tester) async {
    await tester.pumpWidget(app());
    await openDetail(tester);

    await dragRight(tester, 0.5);

    expect(find.text('详情页'), findsNothing);
    expect(find.text('首页'), findsOneWidget);
  });

  testWidgets('右拖不足 30%：回弹，页面还在', (tester) async {
    await tester.pumpWidget(app());
    await openDetail(tester);

    await dragRight(tester, 0.15);

    expect(find.text('详情页'), findsOneWidget);
  });

  testWidgets('快速右滑：距离很短也能退出', (tester) async {
    await tester.pumpWidget(app());
    await openDetail(tester);

    await dragRight(tester, 0.12, fast: true);

    expect(find.text('详情页'), findsNothing);
  });

  testWidgets('后退之后左拖可以再前进', (tester) async {
    await tester.pumpWidget(app());
    await openDetail(tester);
    await dragRight(tester, 0.5);
    expect(find.text('详情页'), findsNothing);

    await dragLeft(tester, 0.5);

    expect(find.text('详情页'), findsOneWidget);
  });

  testWidgets('左拖不足阈值：前进取消，页面不出现', (tester) async {
    await tester.pumpWidget(app());
    await openDetail(tester);
    await dragRight(tester, 0.5);

    await dragLeft(tester, 0.1);

    expect(find.text('详情页'), findsNothing);
  });

  testWidgets('打开新页面会清空前进记录', (tester) async {
    await tester.pumpWidget(app());
    await openDetail(tester);
    await dragRight(tester, 0.5);
    expect(SwipeNavigator.instance.canGoForward, isTrue);

    // 从首页再打开一次，前进记录应当清掉。
    await openDetail(tester);
    expect(SwipeNavigator.instance.canGoForward, isFalse);

    // 左拖没有前进记录可用，不会凭空多出一层页面。
    await dragLeft(tester, 0.5);
    expect(find.text('详情页'), findsOneWidget);
  });

  testWidgets('标记为不响应手势的页面拖不动', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('打开编辑页'));
    await tester.pumpAndSettle();
    expect(find.text('编辑页'), findsOneWidget);

    await dragRight(tester, 0.6);

    expect(find.text('编辑页'), findsOneWidget);
  });

  testWidgets('页面里的横向列表优先拿到手势，不会顺手退出页面', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('打开横向列表'));
    await tester.pumpAndSettle();

    // 在横向列表上右拖：列表已经在最左端，滚动不了，但手势也不该传给导航。
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.timedDragFrom(
      Offset(80, size.height / 2),
      Offset(300, 0),
      const Duration(milliseconds: 900),
    );
    await tester.pumpAndSettle();

    expect(find.text('横向列表页'), findsOneWidget);
  });

  testWidgets('根页面右拖不动（没有可退的页面）', (tester) async {
    await tester.pumpWidget(app());

    await dragRight(tester, 0.6);

    expect(find.text('首页'), findsOneWidget);
  });
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('首页'),
            const SizedBox(height: 24),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  appRoute<void>(
                    builder: (_) => const _DetailPage(),
                    settings: const RouteSettings(name: '/detail'),
                  ),
                ),
                child: const Text('打开详情'),
              ),
            ),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  noSwipeRoute<void>(builder: (_) => const _EditorPage()),
                ),
                child: const Text('打开编辑页'),
              ),
            ),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  appRoute<void>(builder: (_) => const _ScrollPage()),
                ),
                child: const Text('打开横向列表'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('详情页')));
}

class _ScrollPage extends StatelessWidget {
  const _ScrollPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('横向列表页')),
      body: Center(
        child: SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 20,
            itemBuilder: (context, index) => Container(
              width: 120,
              margin: const EdgeInsets.all(8),
              color: Colors.blueGrey.shade100,
              alignment: Alignment.center,
              child: Text('卡片 $index'),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditorPage extends StatelessWidget {
  const _EditorPage();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('编辑页')));
}
