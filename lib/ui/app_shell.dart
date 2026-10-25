import 'package:flutter/material.dart';

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

  late final List<Widget> _pages = [
    HomePage(onOpenSearch: () => setState(() => _index = 2)),
    const BoardsPage(),
    const SearchPage(),
    const ProfilePage(),
  ];

  Future<void> _openCompose() async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ComposePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}
