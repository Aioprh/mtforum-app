import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/pages/thread_page.dart';
import 'package:mt_forum/ui/widgets/back_to_top.dart';
import 'package:mt_forum/ui/widgets/thread_card.dart';
import 'package:mt_forum/ui/widgets/thread_feed.dart';

List<ThreadSummary> _items(int n) => List.generate(
      n,
      (i) => ThreadSummary(
        tid: i + 1,
        title: '帖子 $i',
        url: 'https://bbs.binmt.cc/thread-${i + 1}-1-1.html',
      ),
    );

/// 底部留一块空白，测试点它，避免落到卡片上把帖子页推起来。
const EdgeInsets _padding = EdgeInsets.only(bottom: 420);

Future<void> _pumpFeed(
  WidgetTester tester, {
  required ScrollController controller,
  required bool doubleTapToTop,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: ThreadFeed(
            loader: (page) async => page == 1 ? _items(12) : const <ThreadSummary>[],
            controller: controller,
            doubleTapToTop: doubleTapToTop,
            padding: _padding,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 滚到列表底部，让底部留白进入视口。
Future<void> _scrollToBottom(WidgetTester tester, ScrollController controller) async {
  controller.jumpTo(controller.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

Offset _bottomSpot(WidgetTester tester) {
  final rect = tester.getRect(find.byType(ThreadFeed));
  return Offset(rect.center.dx, rect.bottom - 60);
}

Future<void> _doubleTapAt(WidgetTester tester, Offset spot) async {
  await tester.tapAt(spot);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(spot);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页双击内容区回到顶部', (tester) async {
    final controller = ScrollController();
    await _pumpFeed(tester, controller: controller, doubleTapToTop: true);
    await _scrollToBottom(tester, controller);
    expect(controller.offset, greaterThan(0));

    await _doubleTapAt(tester, _bottomSpot(tester));
    expect(controller.offset, 0);

    controller.dispose();
  });

  testWidgets('单击不回顶', (tester) async {
    final controller = ScrollController();
    await _pumpFeed(tester, controller: controller, doubleTapToTop: true);
    await _scrollToBottom(tester, controller);
    final before = controller.offset;

    await tester.tapAt(_bottomSpot(tester));
    await tester.pumpAndSettle();
    expect(controller.offset, before);

    controller.dispose();
  });

  testWidgets('没开启双击的列表，双击也不动', (tester) async {
    final controller = ScrollController();
    await _pumpFeed(tester, controller: controller, doubleTapToTop: false);
    await _scrollToBottom(tester, controller);
    final before = controller.offset;

    await _doubleTapAt(tester, _bottomSpot(tester));
    expect(controller.offset, before);

    controller.dispose();
  });

  testWidgets('双击卡片本身也回顶，不会顺手把帖子打开', (tester) async {
    final controller = ScrollController();
    await _pumpFeed(tester, controller: controller, doubleTapToTop: true);

    controller.jumpTo(200);
    await tester.pump();
    expect(tester.widget<ThreadCard>(find.byType(ThreadCard).first).onDoubleTap, isNotNull);

    final cards = find.byType(ThreadCard);
    final card = tester.getRect(cards.at(1));
    // 落在卡片自身的留白里，避开标题和头像上那些单独的点击区域。
    final spot = Offset(card.left + 10, card.bottom - 10);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(spot);
    // 用固定时长等回顶动画，别 pumpAndSettle——万一把帖子页推起来了会卡在加载动画上。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.offset, 0);
    expect(find.byType(ThreadPage), findsNothing);

    controller.dispose();
  });

  testWidgets('版块顶栏空白处双击回到顶部', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('逆向交流'),
            flexibleSpace: DoubleTapTopArea(controller: controller),
          ),
          body: ListView.builder(
            controller: controller,
            itemCount: 60,
            itemBuilder: (_, index) => SizedBox(height: 60, child: Text('$index')),
          ),
        ),
      ),
    );

    controller.jumpTo(800);
    await tester.pump();
    expect(controller.offset, 800);

    final bar = tester.getRect(find.byType(AppBar));
    await _doubleTapAt(tester, Offset(bar.right - 90, bar.center.dy));
    expect(controller.offset, 0);

    controller.dispose();
  });
}
