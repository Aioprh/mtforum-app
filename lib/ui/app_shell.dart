import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/boards_page.dart';
import 'pages/compose_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'pages/search_page.dart';

/// 主框架：底部四栏 + 发帖入口。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  DateTime? _lastBackPressedAt;

  late final List<Widget> _pages = [
    HomePage(onOpenSearch: () => setState(() => _index = 2)),
    const BoardsPage(),
    const SearchPage(),
    const ProfilePage(),
  ];

  Future<void> _openCompose() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ComposePage()));
  }

  void _handleBack(bool didPop) {
    if (didPop) return;
    // 子页面由 Navigator 正常返回；只有根页面拦截系统返回手势。
    if (Navigator.of(context).canPop()) return;
    final now = DateTime.now();
    final last = _lastBackPressedAt;
    if (last != null && now.difference(last) <= const Duration(seconds: 2)) {
      unawaited(SystemNavigator.pop());
      return;
    }
    _lastBackPressedAt = now;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('再按一次返回键退出应用'), duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        _handleBack(didPop);
      },
      child: Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: _openCompose,
              icon: const Icon(Icons.edit_rounded, size: 20),
              label: const Text('发帖'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: '版块',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
      ),
    );
  }
}
