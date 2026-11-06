import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/app_theme.dart';
import 'package:mt_forum/core/ui_prefs.dart';
import 'package:mt_forum/state/app_state.dart';
import 'package:mt_forum/ui/widgets/glass_controls.dart';
import 'package:mt_forum/ui/widgets/thread_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppState.instance.glassEnabled = true;
    UiPrefs.glass = true;
    AppState.instance.floatingGlassNav = false;
  });

  tearDown(() {
    AppState.instance.glassEnabled = true;
    UiPrefs.glass = true;
  });

  testWidgets('开启液态玻璃时，底板挂模糊、底色是半透明的', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: GlassBackdrop(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('关掉总开关后，底板不再做背景模糊', (tester) async {
    UiPrefs.glass = false;
    AppState.instance.glassEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: GlassBackdrop(child: SizedBox(width: 40, height: 40)),
        ),
      ),
    );
    // 模糊是最贵的一步，关掉后连 BackdropFilter 都不该存在。
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('关掉后玻璃件底色变成不透明', (tester) async {
    late Color glassFill;
    late Color solidFill;
    late Color solidBorder;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            glassFill = ThreadGlass.fill(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(glassFill.a, lessThan(1.0));

    UiPrefs.glass = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            solidFill = ThreadGlass.fill(context);
            solidBorder = ThreadGlass.borderColor(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(solidFill.a, 1.0, reason: '关掉玻璃后底色必须不透，否则背后内容还是会透上来');
    expect(solidBorder.a, 1.0);
    expect(solidFill, isNot(glassFill));
  });

  testWidgets('GlassCard 关掉玻璃后用实底', (tester) async {
    UiPrefs.glass = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: GlassCard(child: SizedBox(width: 80, height: 40)),
        ),
      ),
    );
    final material = tester.widget<Material>(find.byType(Material).last);
    expect(material.color?.a, 1.0);
  });

  testWidgets('setGlassEnabled 会持久化并停用悬浮玻璃底栏', (tester) async {
    AppState.instance.floatingGlassNav = true;
    expect(AppState.instance.floatingGlassNavActive, isTrue);

    await AppState.instance.setGlassEnabled(false);

    expect(AppState.instance.glassEnabled, isFalse);
    expect(UiPrefs.glass, isFalse);
    expect(AppState.instance.floatingGlassNavActive, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('mt_forum_glass_enabled'), isFalse);
  });
}
