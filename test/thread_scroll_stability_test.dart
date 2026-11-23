import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/pages/thread_page.dart';
import 'package:mt_forum/ui/widgets/post_html_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 长图文帖的滚动稳定性。
///
/// 主题楼动辄几万像素，`SliverList` 滚出 cacheExtent 后会回收它。如果
/// 回收后再进来只铺第一块正文，整篇高度会先缩到一小截，当前滚动位置被
/// clamp，用户看到的就是「突然回到顶部」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  String longHtml([int paragraphs = 120]) => List.generate(
        paragraphs,
        (i) => '<p>首楼第 $i 段内容，用来把这一楼撑得很长。</p>',
      ).join();

  ForumPost opPost() => ForumPost(
        pid: 1,
        uid: 1,
        author: '楼主',
        avatar: '',
        time: '刚刚',
        html: longHtml(),
        floor: 1,
        isOp: true,
      );

  ForumPost reply(int pid, int floor) => ForumPost(
        pid: pid,
        uid: pid,
        author: '回复者$pid',
        avatar: '',
        time: '刚刚',
        html: longHtml(20),
        floor: floor,
      );

  ThreadDetail detailOf(List<ForumPost> posts) => ThreadDetail(
        tid: 1,
        title: '长图文帖',
        fid: 1,
        boardName: '玩机交流',
        author: '楼主',
        time: '刚刚',
        views: 1,
        replies: posts.length - 1,
        posts: posts,
        formhash: 'x',
        hasMore: false,
        isLoggedIn: true,
        uid: 1,
      );

  testWidgets('主题楼滚出视口后仍保留，滚动位置不会被带回顶部', (tester) async {
    tester.view.physicalSize = const Size(1264, 2800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final posts = [opPost(), for (var i = 2; i <= 6; i++) reply(i, i)];
    await tester.pumpWidget(
      MaterialApp(
        home: ThreadPage.preview(detail: detailOf(posts), posts: posts),
      ),
    );
    // 首楼分帧铺开，多 pump 几帧让它铺满。
    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }

    final position = tester.widget<ListView>(find.byType(ListView).first).controller!.position;
    expect(position.maxScrollExtent, greaterThan(1000));

    // 直接滑到评论区底部。
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    // 首楼已远在 cacheExtent 之外，靠 keepAlive 留在树上。
    expect(
      find.textContaining('首楼第 119 段', skipOffstage: false),
      findsOneWidget,
      reason: '主题楼被回收后再重建会让整篇高度先缩后涨，滚动位置就会跑',
    );

    // 从评论区往上翻：位置正常回退，不会被夹到 0。
    final target = position.maxScrollExtent * 0.45;
    position.jumpTo(target);
    await tester.pump();
    expect(position.pixels, closeTo(target, 1));
    expect(position.pixels, greaterThan(1000));
  });

  testWidgets('非分块模式第一帧就是完整高度', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: PostHtmlView(html: longHtml(), progressive: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('首楼第 119 段', skipOffstage: false), findsOneWidget);
  });

  testWidgets('分块模式按帧补齐，最终不会漏内容', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: PostHtmlView(html: longHtml(), progressive: true),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('首楼第 119 段', skipOffstage: false), findsNothing);

    for (var i = 0; i < 20; i++) {
      await tester.pump();
    }
    expect(find.textContaining('首楼第 119 段', skipOffstage: false), findsOneWidget);
  });
}
