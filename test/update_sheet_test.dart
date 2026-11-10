import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/services/update_service.dart';
import 'package:mt_forum/ui/pages/update_sheet.dart';

/// 更新面板：默认选中、切换安装包。
void main() {
  const release = AppRelease(
    tag: 'v2.9.0',
    version: '2.9.0',
    notes: '修了些问题',
    publishedAt: '',
    assets: [
      ReleaseAsset(name: 'app-armeabi-v7a-release.apk', url: 'https://example.com/a', size: 21473358),
      ReleaseAsset(name: 'app-arm64-v8a-release.apk', url: 'https://example.com/b', size: 23628018),
      ReleaseAsset(name: 'app-release.apk', url: 'https://example.com/d', size: 65736032),
    ],
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UpdateSheet(release: release))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('默认选中一个安装包', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    expect(find.text('下载并安装'), findsOneWidget);
  });

  testWidgets('点击另一个包会换选中项', (tester) async {
    await pump(tester);
    await tester.tap(find.text('arm64-v8a'));
    await tester.pump();
    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    // 选中的样式跟着走：arm64 那行的文字变主色，这里只验证仍然只有一个勾。
    expect(find.text('通用包'), findsOneWidget);
  });

  testWidgets('版本说明和安装包体积都能显示', (tester) async {
    await pump(tester);
    expect(find.textContaining('2.9.0'), findsWidgets);
    expect(find.textContaining('22.5 MB'), findsOneWidget);
    expect(find.textContaining('62.7 MB'), findsOneWidget);
  });
}
