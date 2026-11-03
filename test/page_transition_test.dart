import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/app_theme.dart';

/// 页面转场与预测性返回。
///
/// 历史上这里守着「转场半程不能整屏发白」：Android 默认的 Zoom 转场会
/// 把旧页缩成圆角卡片、再盖一层 surface 遮罩，浅色主题下半程像蒙了层
/// 毛玻璃，当时为此把全平台都换成了 Cupertino 的横向位移。
///
/// 现在 Android 要用系统的预测性返回（手势跟手缩放），而
/// `PredictiveBackPageTransitionsBuilder` 在非手势场景会回退到
/// FadeForwards——新页从左滑入、旧页不动，遮罩颜色由 `fallbackColor`
/// 决定。所以「不发白」这条约束换了个抓手：盯住 fallbackColor 必须是
/// 透明，别再让遮罩回来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android 注册预测性返回转场，且兜底遮罩透明', () {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final builder = theme.pageTransitionsTheme.builders[TargetPlatform.android];
      expect(
        builder,
        isA<PredictiveBackPageTransitionsBuilder>(),
        reason: 'Android 没挂预测性返回转场，手势只会直接返回、没有跟手预览',
      );
      expect(
        (builder! as PredictiveBackPageTransitionsBuilder).fallbackColor,
        Colors.transparent,
        reason: '兜底遮罩一旦有颜色，浅色主题下半程就会整屏发白',
      );
    }
  });

  test('其它平台仍是 Cupertino 横向转场', () {
    const cupertino = <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ];
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      for (final platform in cupertino) {
        expect(
          theme.pageTransitionsTheme.builders[platform],
          isA<CupertinoPageTransitionsBuilder>(),
          reason: '${platform.name} 被换回了默认转场，切页会白屏、叠影',
        );
      }
    }
  });

  test('清单里打开了 enableOnBackInvokedCallback', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      RegExp(r'android:enableOnBackInvokedCallback="true"').hasMatch(manifest),
      isTrue,
      reason: '不开这个开关，系统不会把返回手势交给 Flutter，也就没有跟手预览',
    );
    // 属性必须落在 <application> 上：写在 activity 上对 androidx 的
    // OnBackInvokedDispatcher 无效，手势会直接回退到旧的分发路径。
    final application = RegExp(r'<application[^>]*>').firstMatch(manifest)?.group(0) ?? '';
    expect(application, contains('enableOnBackInvokedCallback'));
  });

  testWidgets('普通 push 不会盖白色遮罩', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Center(child: Text('第二页'))),
                  ),
                ),
                child: const Text('去第二页'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('去第二页'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    // 半程时整屏纯白只可能来自兜底遮罩。透明的 scrim 不会建出铺满屏幕的
    // 白色 ColoredBox，这里用尺寸把它和页面自身背景区分开。
    final screen = tester.getSize(find.byType(MaterialApp));
    final whiteScrim = find.byWidgetPredicate((widget) {
      if (widget is! ColoredBox) return false;
      final color = widget.color;
      return color.a > 0.5 && color.r > 0.95 && color.g > 0.95 && color.b > 0.95;
    });
    for (final element in whiteScrim.evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      expect(
        box.size.width >= screen.width * 0.98 && box.size.height >= screen.height * 0.9,
        isFalse,
        reason: '转场里出现了整屏白色遮罩',
      );
    }
    await tester.pumpAndSettle();
  });
}
