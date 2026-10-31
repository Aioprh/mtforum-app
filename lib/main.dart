import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'mcp/mcp_server.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/navigation/swipe_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await AppState.instance.bootstrapLocal();
  } catch (_) {
    // 本地缓存初始化失败也应进入应用。
  }
  // 上次开着 MCP 服务的话，开机自动恢复监听；关着就只读一下配置。
  unawaited(McpServer.instance.load());
  runApp(const MtForumApp());
}

class MtForumApp extends StatelessWidget {
  const MtForumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppState.instance,
      builder: (context, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        navigatorKey: SwipeNavigator.instance.navigatorKey,
        navigatorObservers: [SwipeNavigator.instance],
        // 手势层铺在 Navigator 外面：页面内部的横向滚动（图片翻页、表格）
        // 会先拿到手势，抢不到的地方才归导航用。
        builder: (context, child) =>
            SwipeGestureRegion(child: child ?? const SizedBox.shrink()),
        theme: AppTheme.light(AppState.instance.themeSeedColor),
        darkTheme: AppTheme.dark(AppState.instance.themeSeedColor),
        themeMode: AppState.instance.themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppShell(),
      ),
    );
  }
}
