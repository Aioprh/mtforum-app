import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'back_to_top.dart';
import 'thread_glass.dart';

/// 透明玻璃顶栏。
///
/// 和帖子页顶栏同一套取色：底色透明，正文从 `flexibleSpace` 里那块玻璃背后
/// 滚过，模糊才有内容可糊。
///
/// 用它的页面必须同时做两件事，缺一件就会露馅：
/// 1. `Scaffold.extendBodyBehindAppBar: true`，否则 body 从顶栏下沿开始，
///    玻璃背后什么都没有；
/// 2. 列表顶部补 [glassTopInset] 的留白，否则第一条内容被顶栏压住。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.doubleTapController,
    this.automaticallyImplyLeading = true,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  /// 传入滚动控制器后，顶栏空白处双击回顶。标题和按钮在上层，不受影响。
  final ScrollController? doubleTapController;

  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      // 背景透明时 AppBar 会把透明当成「很暗」，浅色主题下状态栏图标会变白。
      systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      flexibleSpace: Stack(
        fit: StackFit.expand,
        children: [
          GlassBackdrop(
            showBorder: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: ThreadGlass.borderColor(context), width: 0.6),
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (doubleTapController != null) DoubleTapTopArea(controller: doubleTapController!),
        ],
      ),
    );
  }
}

/// 玻璃顶栏下正文需要空出的高度：状态栏 + 顶栏（含 [TabBar] 这类 bottom）。
double glassTopInset(BuildContext context, {double bottomHeight = 0}) =>
    MediaQuery.paddingOf(context).top + kToolbarHeight + bottomHeight;
