import 'package:flutter/material.dart';

/// 卡片式返回转场。
///
/// 系统预测性返回本身只负责「当前页」：手势往回拖时它缩到 0.9、圆角 32、
/// 往边上挪一点，但底下那一页原地不动——于是四周露出来的是硬邦邦的满屏
/// 页面，看着就像一张纸片贴在另一张纸上，没有层次。
///
/// 这里在被覆盖的那一页上再补一层：随上层推进缩小到 0.94、收出圆角、
/// 压一层暗色。两张卡片一明一暗、一大一小叠着，才是系统「关于本机」
/// 那种返回预览的样子。
class CardPageTransitionsBuilder extends PageTransitionsBuilder {
  const CardPageTransitionsBuilder({this.fallbackColor = Colors.transparent});

  /// 不做预测返回时的兜底遮罩色。保持透明，否则浅色主题下半程整屏发白。
  final Color? fallbackColor;

  @override
  Duration get transitionDuration =>
      const PredictiveBackPageTransitionsBuilder().transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 跟手、缩放、圆角、取消回弹仍然交给框架，别自己重写一套手势检测。
    final page = PredictiveBackPageTransitionsBuilder(fallbackColor: fallbackColor)
        .buildTransitions(route, context, animation, secondaryAnimation, child);
    return _StackedPage(secondaryAnimation: secondaryAnimation, child: page);
  }
}

/// 被上层盖住时的形态：缩小、圆角、压暗。
class _StackedPage extends StatelessWidget {
  const _StackedPage({required this.secondaryAnimation, required this.child});

  final Animation<double> secondaryAnimation;
  final Widget child;

  /// 完全被盖住时的缩放。再小就会露太多底，像在翻相册。
  static const double _minScale = 0.94;
  static const double _radius = 26;
  static const double _dim = 0.18;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: secondaryAnimation,
      builder: (context, child) {
        final raw = secondaryAnimation.value.clamp(0.0, 1.0);
        if (raw <= 0.001) return child!;
        final t = Curves.easeOutCubic.transform(raw);
        return Transform.scale(
          scale: 1 - (1 - _minScale) * t,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_radius * t),
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                child!,
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(color: Colors.black.withValues(alpha: _dim * t)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: child,
    );
  }
}
