import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/ui/widgets/pm_composer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 私信输入栏要补齐官网编辑器那排工具，且插入的是 BBCode。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host({
    required TextEditingController controller,
    required VoidCallback onSend,
    ValueChanged<bool>? onEmojiChanged,
    bool showEmoji = false,
    bool sending = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PmComposer(
            controller: controller,
            onSend: onSend,
            onEmojiChanged: onEmojiChanged ?? (_) {},
            showEmoji: showEmoji,
            sending: sending,
          ),
        ),
      ),
    );
  }

  testWidgets('工具条包含表情、加粗、颜色、链接、引用、代码', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller: controller, onSend: () {}));
    await tester.pumpAndSettle();

    for (final tooltip in <String>['官方表情', '加粗', '文字颜色', '插入链接', '引用', '代码']) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: '缺少「$tooltip」工具');
    }
  });

  testWidgets('点加粗在光标处插入 [b]…[/b]', (tester) async {
    final controller = TextEditingController(text: '你好');
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pumpWidget(host(controller: controller, onSend: () {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('加粗'));
    await tester.pump();

    expect(controller.text, '你好[b][/b]');
    expect(controller.selection.baseOffset, '你好[b]'.length);
  });

  testWidgets('点引用、代码同样插入包裹标记', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller: controller, onSend: () {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('引用'));
    await tester.pump();
    expect(controller.text, '[quote][/quote]');

    controller.clear();
    await tester.tap(find.byTooltip('代码'));
    await tester.pump();
    expect(controller.text, '[code][/code]');
  });

  testWidgets('表情按钮把开关交给页面', (tester) async {
    final controller = TextEditingController();
    var toggles = 0;
    await tester.pumpWidget(
      host(controller: controller, onSend: () {}, onEmojiChanged: (_) => toggles++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('官方表情'));
    await tester.pump();
    expect(toggles, 1);
  });

  testWidgets('空内容发送键不可用，写了字才点亮', (tester) async {
    final controller = TextEditingController();
    var sent = 0;
    await tester.pumpWidget(host(controller: controller, onSend: () => sent++));
    await tester.pumpAndSettle();

    IconButton button() => tester.widget<IconButton>(find.byType(IconButton));
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '在吗');
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    expect(sent, 1);
  });
}
