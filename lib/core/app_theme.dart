import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';

class AppTheme {
  const AppTheme._();

  static const Color defaultSeed = Color(0xFF607080);

  static ThemeData light([Color seed = defaultSeed]) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return _base(scheme, const Color(0xFFF5F7F9));
  }

  static ThemeData dark([Color seed = defaultSeed]) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return _base(scheme, const Color(0xFF0D1117));
  }

  static ThemeData _base(ColorScheme scheme, Color background) {
    final isDark = scheme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF151A21) : Colors.white;
    final inputStroke = isDark ? const Color(0xFF2A323C) : const Color(0xFFE4E8EC);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(surface: surface),
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC', 'Source Han Sans SC'],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? const Color(0xFF232A33) : const Color(0xFFEDF0F3)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 11.5,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 23,
              color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
            )),
      ),
      // 全局兜底：万一还有没走 GlassField 的输入框，也不至于冒出 Material
      // 的下划线或方框。数值和 GlassField 对齐（14 圆角、发丝描边、淡白底）。
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: isDark ? 0.08 : 0.44),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputStroke, width: 0.9),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputStroke, width: 0.9),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputStroke, width: 0.9),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: isDark ? 0.55 : 0.42),
            width: 1.2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // 宽度随内容：`Size.fromHeight` 的宽是无穷大，会让对话框 actions
          // 里的按钮各占一行——「取消」单独一行、「确认」撑满下一行。
          // 需要通栏的页面自己指定 Size.fromHeight。
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      // 页面转场。
      //
      // 早先全平台都用 Cupertino 横向位移，是为了躲开 Zoom 转场：它把旧页
      // 缩成圆角卡片、再垫一层 surface 遮罩，入场又把新页从 0.85 缩放淡入，
      // 半程整屏发白，前后两页同时半透明叠在一起，浅色主题像糊了层毛玻璃。
      //
      // 现在 Android 要接系统的预测性返回（手势跟手），改用它自己的转场
      // builder；其余平台仍保持 Cupertino。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          // Android 走系统的预测性返回：手势往右拖时页面跟着缩、跟着挪，
          // 松手才决定是返回还是取消。三个细节：
          //
          // 1. 只有「手势进行中」才播跟手动画，普通 push（点按钮、代码里
          //    push）交给 FadeForwards 兜底——这是 3.32 之后的 Android 默认
          //    转场，新页从左滑入，旧页不动，不像旧的 Zoom 那样把旧页缩成
          //    圆角卡片再盖一层白膜。
          // 2. fallbackColor 必须是透明：它就是这个兜底转场的遮罩色，留空
          //    会按主题取 surface，浅色主题下半程整屏发白——之前为此专门
          //    退回过 Cupertino。
          // 3. 其它平台没有预测性返回，仍用 Cupertino 的横向位移。
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(
            fallbackColor: Colors.transparent,
          ),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: isDark ? const Color(0xFF262E38) : const Color(0xFF252C35),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF222A34) : const Color(0xFFEDF0F3),
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        showDragHandle: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF1B222B) : const Color(0xFFF2F4F7),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }

  static const String siteName = AppConfig.siteName;
}
