import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

import '../state/app_state.dart';

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
      child: AnimatedBuilder(
        animation: AppState.instance,
        builder: (context, _) => Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: _openCompose,
              icon: const Icon(Icons.edit_rounded, size: 20),
              label: const Text('发帖'),
            )
          : null,
      bottomNavigationBar: AppState.instance.floatingGlassNav
          ? _buildFloatingGlassNav(context)
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '首页'),
                NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: '版块'),
                NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded), label: '搜索'),
                NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: '我的'),
              ],
            ),
      ),
      ),
    );
  }

  Widget _buildFloatingGlassNav(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const items = [
      (Icons.home_outlined, Icons.home_rounded, '首页'),
      (Icons.grid_view_outlined, Icons.grid_view_rounded, '版块'),
      (Icons.search_rounded, Icons.search_rounded, '搜索'),
      (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
    ];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF202630) : Colors.white).withValues(alpha: isDark ? 0.78 : 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                BoxShadow(color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.8), blurRadius: 1, offset: const Offset(0, 1)),
              ],
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => setState(() => _index = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(
                          color: _index == i ? scheme.primary.withValues(alpha: isDark ? 0.28 : 0.14) : Colors.transparent,
                          borderRadius: BorderRadius.circular(22),
                          border: _index == i ? Border.all(color: scheme.primary.withValues(alpha: 0.22)) : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_index == i ? items[i].$2 : items[i].$1, size: 22, color: _index == i ? scheme.primary : scheme.onSurfaceVariant),
                            const SizedBox(height: 3),
                            Text(items[i].$3, style: TextStyle(fontSize: 11, fontWeight: _index == i ? FontWeight.w700 : FontWeight.w500, color: _index == i ? scheme.primary : scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}