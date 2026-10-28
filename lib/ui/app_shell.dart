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
      extendBody: AppState.instance.floatingGlassNav,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
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
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        const Color(0xFF303945).withValues(alpha: 0.25),
                        const Color(0xFF171D26).withValues(alpha: 0.16),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.25),
                        const Color(0xFFF1F5FA).withValues(alpha: 0.16),
                      ],
              ),
              border: Border.all(
                color: (isDark ? Colors.white : scheme.outlineVariant)
                    .withValues(alpha: isDark ? 0.16 : 0.30),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                  blurRadius: 30,
                  spreadRadius: 0,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.62),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                // 顶部柔和高光，让玻璃边缘更有通透感。
                Positioned(
                  left: 24,
                  right: 24,
                  top: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 1.2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: isDark ? 0.20 : 0.72),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: _index == i,
                            label: items[i].$3,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => setState(() => _index = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  gradient: _index == i
                                      ? LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            scheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
                                            scheme.primary.withValues(alpha: isDark ? 0.12 : 0.04),
                                          ],
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(24),
                                  border: _index == i
                                      ? Border.all(
                                          color: scheme.primary.withValues(alpha: 0.18),
                                        )
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 180),
                                      child: Icon(
                                        _index == i ? items[i].$2 : items[i].$1,
                                        key: ValueKey('nav-icon-$i-$_index'),
                                        size: 22,
                                        color: _index == i
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      items[i].$3,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.15,
                                        letterSpacing: 0.1,
                                        fontWeight: _index == i
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: _index == i
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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