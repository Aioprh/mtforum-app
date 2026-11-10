import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/models.dart';
import 'package:mt_forum/ui/pages/region_picker_sheet.dart';

/// 居住地选择器：逐级下钻、回填和「没有下级」的兜底。
void main() {
  Future<List<RegionOption>> fakeLoader({int provinceId = 0, int cityId = 0}) async {
    if (provinceId == 0) {
      return const [
        RegionOption(name: '天津市', id: 2),
        RegionOption(name: '广东省', id: 19),
        RegionOption(name: '海外', id: 35),
      ];
    }
    if (provinceId == 35) return const [];
    if (cityId == 0) {
      return const [
        RegionOption(name: '大港区', id: 63),
        RegionOption(name: '和平区', id: 55),
      ];
    }
    if (cityId == 63) {
      return const [
        RegionOption(name: '中塘镇', id: 968),
        RegionOption(name: '古林街道', id: 969),
      ];
    }
    return const [];
  }

  /// 打开面板，返回「已返回结果」的容器；面板 pop 之后才会有值。
  Future<List<RegionPick?>> openPicker(
    WidgetTester tester, {
    String province = '',
    String city = '',
    String dist = '',
    Future<List<RegionOption>> Function({int provinceId, int cityId})? loader,
  }) async {
    final box = <RegionPick?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  box.add(
                    await RegionPickerSheet.show(
                      context,
                      loader: loader ?? fakeLoader,
                      province: province,
                      city: city,
                      dist: dist,
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    return box;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('省 → 市 → 区 逐级选择后返回结果', (tester) async {
    final box = await openPicker(tester);

    expect(find.text('选择省份'), findsOneWidget);
    expect(find.text('天津市'), findsOneWidget);

    await tester.tap(find.text('天津市'));
    await settle(tester);
    expect(find.text('选择城市'), findsOneWidget);
    expect(find.text('大港区'), findsOneWidget);

    await tester.tap(find.text('大港区'));
    await settle(tester);
    expect(find.text('选择区县'), findsOneWidget);
    expect(find.text('中塘镇'), findsOneWidget);

    await tester.tap(find.text('中塘镇'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('选择区县'), findsNothing);
    expect(box.single?.text, '天津市 大港区 中塘镇');
  });

  testWidgets('打开时按已有地址回填到区县', (tester) async {
    final box = await openPicker(tester, province: '天津市', city: '大港区');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('选择区县'), findsOneWidget);
    expect(find.text('中塘镇'), findsOneWidget);
    // 面包屑上能一眼看到省市两级。
    expect(find.text('天津市'), findsWidgets);
    expect(find.text('大港区'), findsWidgets);
    expect(box, isEmpty);
  });

  testWidgets('没有下级的省份选完直接交卷', (tester) async {
    final box = await openPicker(tester);

    await tester.tap(find.text('海外'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('选择省份'), findsNothing);
    expect(box.single?.text, '海外');
  });

  testWidgets('清除居住地返回空结果', (tester) async {
    final box = await openPicker(tester, province: '天津市', city: '大港区', dist: '中塘镇');

    await tester.tap(find.text('清除居住地'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('选择区县'), findsNothing);
    expect(box.single?.text, isEmpty);
  });

  testWidgets('加载失败显示错误，重试后恢复', (tester) async {
    var fail = true;
    Future<List<RegionOption>> loader({int provinceId = 0, int cityId = 0}) async {
      if (fail) throw Exception('网络开小差');
      return const [RegionOption(name: '天津市', id: 2)];
    }

    await openPicker(tester, loader: loader);
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.textContaining('网络开小差'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('重试'));
    await settle(tester);
    expect(find.text('天津市'), findsOneWidget);
  });
}
