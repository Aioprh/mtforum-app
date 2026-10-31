import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 手势导航基础设施。
///
/// 三件事：
/// 1. [SwipePageRoute]：页面转场由路由自己的动画控制器驱动，手势可以直接改
///    它的 `value`，所以页面能跟着手指走，而不是等松手才动。
/// 2. [SwipeNavigator]：记录路由栈，并在页面被关闭时留下快照，形成「前进栈」。
///    Flutter 的 Navigator 只有后退没有前进，前进记录得自己攒。
/// 3. [SwipeGestureRegion]：铺在整个 App 外层的横向拖动手势，右拖后退、左拖前进。

/// 一个可重建的路由快照。
///
/// 前进时用它重新 push 一个页面。页面状态不会保留（Flutter 的 Route 被移除
/// 后就销毁了），所以前进等于重新打开一次，数据会重新拉取。
@immutable
class RouteSnapshot {
  const RouteSnapshot({
    required this.builder,
    required this.settings,
    required this.allowSwipe,
  });

  final WidgetBuilder builder;
  final RouteSettings settings;
  final bool allowSwipe;

  Route<dynamic> build({required bool holdAtStart}) => SwipePageRoute<dynamic>(
    builder: builder,
    settings: settings,
    allowSwipe: allowSwipe,
    holdAtStart: holdAtStart,
    replayed: true,
  );
}

/// 支持手势拖动的页面路由。
///
/// 转场是「新页面从右侧滑入 + 原页面左移四分之一」，两条都由路由动画驱动；
/// 手势把动画值停在中间，视觉上就是页面被手指拖着走。
class SwipePageRoute<T> extends PageRoute<T> {
  SwipePageRoute({
    required this.builder,
    super.settings,
    this.allowSwipe = true,
    this.holdAtStart = false,
    this.replayed = false,
  });

  final WidgetBuilder builder;

  /// 手势在该页面是否生效。编辑、登录、图片浏览这类页面关掉：
  /// 拖到一半退出去会把用户填的内容丢掉，图片浏览还要留给左右切图。
  final bool allowSwipe;

  /// 由「前进」手势创建的路由：停在起点，等手指驱动，不自动播放入场动画。
  final bool holdAtStart;

  /// 由前进记录重放出来的路由。重放不算「打开新页面」，不能清空前进栈。
  final bool replayed;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 不用曲线：手势中途改的是 animation.value，曲线会让页面位移和手指对不上
    // （拖一半页面已经跑到八九成，手感会飘）。
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.25, 0),
      ).animate(secondaryAnimation),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  @override
  TickerFuture didPush() {
    final future = super.didPush();
    if (holdAtStart) {
      // push 时 Navigator 会让动画从头播一遍，这里立刻刹车并钉在起点，
      // 之后由手势接管。同一帧内完成，不会闪一下。
      controller!.stop();
      controller!.value = 0;
    }
    return future;
  }

  /// 手势层不直接碰受保护的 controller，走这三个方法。
  ///
  /// [progress] 为 1 表示页面完全就位，0 表示滑出屏幕。
  void beginDrag() => controller?.stop();

  void dragTo(double progress) {
    final target = controller;
    if (target == null) return;
    target.value = progress.clamp(0.0, 1.0);
  }

  void settleTo(double progress, {Duration duration = const Duration(milliseconds: 220)}) {
    controller?.animateTo(progress, duration: duration, curve: Curves.easeOut);
  }

  RouteSnapshot snapshot() => RouteSnapshot(
    builder: builder,
    settings: settings,
    allowSwipe: allowSwipe,
  );
}

/// 页面自己接管前进/后退的入口，目前只有内置浏览器用到：
/// 网页还能后退时先退网页，退到头才关页面。
class SwipeBackInterceptor {
  SwipeBackInterceptor({
    required this.canGoBack,
    required this.goBack,
    this.canGoForward,
    this.goForward,
  });

  /// 必须同步返回——手势判定开始那一帧就要知道能不能拦，不能等异步查询。
  final bool Function() canGoBack;
  final VoidCallback goBack;

  /// 网页历史前进，可选。没有网页的页面留空。
  final bool Function()? canGoForward;
  final VoidCallback? goForward;

  /// 归属路由：只有它处在栈顶时拦截才生效，
  /// 否则在它上面打开的页面会被下层的浏览器抢走手势。
  Route<dynamic>? _owner;
}

/// 路由栈 + 前进栈 + 拦截器登记。
class SwipeNavigator extends NavigatorObserver {
  SwipeNavigator._();

  static final SwipeNavigator instance = SwipeNavigator._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final List<Route<dynamic>> _stack = <Route<dynamic>>[];
  final List<RouteSnapshot> _forward = <RouteSnapshot>[];
  final List<SwipeBackInterceptor> _interceptors = <SwipeBackInterceptor>[];

  NavigatorState? get navigatorState => navigatorKey.currentState;

  /// 栈顶必须是可手势的路由，否则（对话框、弹层、根页面）整个手势不响应。
  SwipePageRoute<dynamic>? get topSwipeRoute {
    if (_stack.isEmpty) return null;
    final top = _stack.last;
    if (top is! SwipePageRoute<dynamic>) return null;
    return top.allowSwipe ? top : null;
  }

  bool get canGoForward => _forward.isNotEmpty;

  /// 栈顶是对话框、弹层一类的路由。
  bool get topIsPopup => _stack.isNotEmpty && _stack.last is PopupRoute<dynamic>;

  /// 测试用：清空栈与前进记录（单例跨用例会串）。
  @visibleForTesting
  void resetForTest() {
    _stack.clear();
    _forward.clear();
    _interceptors.clear();
  }

  SwipeBackInterceptor? get topInterceptor =>
      _interceptors.isEmpty ? null : _interceptors.last;

  /// 只取属于该页面的拦截器。
  SwipeBackInterceptor? interceptorFor(Route<dynamic> route) {
    for (final interceptor in _interceptors.reversed) {
      if (interceptor._owner == route) return interceptor;
    }
    return null;
  }

  void registerInterceptor(SwipeBackInterceptor interceptor) {
    interceptor._owner = _stack.isEmpty ? null : _stack.last;
    _interceptors.add(interceptor);
  }

  void unregisterInterceptor(SwipeBackInterceptor interceptor) =>
      _interceptors.remove(interceptor);

  /// 取出最近一条前进记录。手势取消时用 [restoreForward] 放回去。
  RouteSnapshot? takeForward() {
    if (_forward.isEmpty) return null;
    return _forward.removeLast();
  }

  void restoreForward(RouteSnapshot snapshot) => _forward.add(snapshot);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 打开新页面清空前进记录；重放前进记录本身不算打开新页面。
    if (route is SwipePageRoute<dynamic> && !route.replayed) {
      _forward.clear();
    }
    _stack.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    // 只留可手势页面的记录：编辑页、登录页被关掉之后不该出现在前进记录里。
    if (route is SwipePageRoute<dynamic> && route.allowSwipe) {
      _forward.add(route.snapshot());
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

/// 全屏横向手势层。右拖后退，左拖前进。
class SwipeGestureRegion extends StatefulWidget {
  const SwipeGestureRegion({super.key, required this.child});

  final Widget child;

  @override
  State<SwipeGestureRegion> createState() => _SwipeGestureRegionState();
}

enum _DragMode { idle, back, forward, ignored }

class _SwipeGestureRegionState extends State<SwipeGestureRegion> {
  _DragMode _mode = _DragMode.idle;
  double _dx = 0;
  double _width = 1;
  SwipePageRoute<dynamic>? _backRoute;
  SwipeBackInterceptor? _backInterceptor;
  SwipeBackInterceptor? _webForward;
  RouteSnapshot? _pendingForward;

  /// 前进方向没有可以提前摆好的页面（它已经被关掉了），所以拖动时把整个
  /// App 往左推一点，松手后才真正 push。减速系数让位移只有手指的一半，
  /// 和 iOS 的边缘回退手感一致。
  double _shift = 0;
  Duration _shiftDuration = Duration.zero;

  void _onStart(DragStartDetails details) {
    _mode = _DragMode.idle;
    _dx = 0;
    _backRoute = null;
    _backInterceptor = null;
    _webForward = null;
    _pendingForward = null;
    _width = MediaQuery.sizeOf(context).width;
    if (_width <= 0) _width = 1;
    _shiftDuration = Duration.zero;
  }

  void _onUpdate(DragUpdateDetails details) {
    _dx += details.primaryDelta ?? 0;
    if (_mode == _DragMode.idle) {
      // 方向还没定之前先不接管，避免一按下就把页面挪几像素。
      if (_dx.abs() < 4) return;
      _decide(_dx > 0);
      if (_mode == _DragMode.idle || _mode == _DragMode.ignored) return;
    }
    if (_mode == _DragMode.back) {
      final progress = (_dx / _width).clamp(0.0, 1.0);
      _backRoute?.dragTo(1 - progress);
    } else if (_mode == _DragMode.forward) {
      _applyShift((-_dx * 0.6).clamp(0.0, _width * 0.4));
    }
  }

  void _applyShift(double value) {
    _shiftDuration = Duration.zero;
    if ((value - _shift).abs() < 0.5) return;
    setState(() => _shift = value);
  }

  void _releaseShift() {
    if (_shift == 0) return;
    setState(() {
      _shiftDuration = const Duration(milliseconds: 240);
      _shift = 0;
    });
  }

  void _resetShiftNow() {
    if (_shift == 0) return;
    setState(() {
      _shiftDuration = Duration.zero;
      _shift = 0;
    });
  }

  /// 方向确定后决定这一次拖动归谁。
  void _decide(bool toRight) {
    final nav = SwipeNavigator.instance;
    final navigator = nav.navigatorState;
    if (navigator == null) {
      _mode = _DragMode.ignored;
      return;
    }
    final route = nav.topSwipeRoute;

    if (toRight) {
      // 后退要求栈顶是允许手势的页面；根页面、对话框、编辑页都不响应。
      if (route == null) {
        _mode = _DragMode.ignored;
        return;
      }
      // 网页优先走网页历史：能退就退网页，页面跟着手动，松手回弹。
      final interceptor = nav.interceptorFor(route);
      if (interceptor != null && interceptor.canGoBack()) {
        _backInterceptor = interceptor;
        _backRoute = route;
        _mode = _DragMode.back;
        route.beginDrag();
        return;
      }
      if (!navigator.canPop()) {
        _mode = _DragMode.ignored;
        return;
      }
      _backRoute = route;
      _mode = _DragMode.back;
      route.beginDrag();
      return;
    }

    // 向左：根页面也能前进（记录来自刚被关掉的页面），但对话框上不触发。
    if (nav.topIsPopup) {
      _mode = _DragMode.ignored;
      return;
    }
    final interceptor = route == null ? null : nav.interceptorFor(route);
    final webForward = interceptor != null && (interceptor.canGoForward?.call() ?? false);
    if (!webForward && !nav.canGoForward) {
      _mode = _DragMode.ignored;
      return;
    }
    _webForward = webForward ? interceptor : null;
    if (!webForward) _pendingForward = nav.takeForward();
    _mode = _DragMode.forward;
  }

  void _onEnd(DragEndDetails details) {
    final mode = _mode;
    final dx = _dx;
    _mode = _DragMode.idle;
    _dx = 0;
    if (mode == _DragMode.back) {
      _finishBack(details.primaryVelocity ?? 0, dx);
    } else if (mode == _DragMode.forward) {
      _finishForward(details.primaryVelocity ?? 0, dx);
    }
  }

  void _onCancel() {
    final mode = _mode;
    final dx = _dx;
    _mode = _DragMode.idle;
    _dx = 0;
    if (mode == _DragMode.back) {
      _finishBack(0, dx);
    } else if (mode == _DragMode.forward) {
      _finishForward(0, dx);
    }
  }

  bool _shouldComplete(double velocity, double dx) {
    if (dx.abs() >= _width * 0.3) return true;
    // 快速滑动：和拖动方向同向、超过阈值就认，不管走了多远。
    return velocity.abs() > 700 && velocity.sign == dx.sign;
  }

  void _finishBack(double velocity, double dx) {
    final route = _backRoute;
    final interceptor = _backInterceptor;
    final intercepted = _backInterceptor != null;
    _backRoute = null;
    _backInterceptor = null;
    if (route == null) return;

    if (intercepted) {
      // 网页后退不离开页面，所以把页面弹回原位，同时执行网页历史后退。
      route.settleTo(1, duration: const Duration(milliseconds: 180));
      interceptor?.goBack();
      return;
    }

    if (_shouldComplete(velocity, dx)) {
      SwipeNavigator.instance.navigatorState?.pop();
    } else {
      route.settleTo(1);
    }
  }

  void _finishForward(double velocity, double dx) {
    final web = _webForward;
    final snapshot = _pendingForward;
    _webForward = null;
    _pendingForward = null;

    if (!_shouldComplete(-velocity, -dx)) {
      // 取消：把记录放回前进栈，页面回弹。
      if (snapshot != null) SwipeNavigator.instance.restoreForward(snapshot);
      _releaseShift();
      return;
    }

    if (web != null) {
      web.goForward?.call();
      _releaseShift();
      return;
    }

    if (snapshot == null) {
      _releaseShift();
      return;
    }
    // 先让页面回正，再 push：push 会插入新的 overlay，正在进行的拖动会被打断，
    // 所以只能在手势结束之后做。
    _resetShiftNow();
    SwipeNavigator.instance.navigatorState?.push(snapshot.build(holdAtStart: false));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _shift),
        duration: _shiftDuration,
        curve: Curves.easeOut,
        builder: (context, value, child) {
          if (value.abs() < 0.5) return child!;
          return Transform.translate(offset: Offset(-value, 0), child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// 统一的页面路由入口。
///
/// 所有 `Navigator.push` 都走这里，手势导航才覆盖得到；直接 new 一个
/// `MaterialPageRoute` 的页面无法拖动。
Route<T> appRoute<T>({
  required WidgetBuilder builder,
  bool gestures = true,
  RouteSettings? settings,
}) => SwipePageRoute<T>(
  builder: builder,
  allowSwipe: gestures,
  settings: settings,
);

/// 不参与手势导航的页面：编辑、登录、图片浏览。
///
/// 参数和 [appRoute] 保持一致，调用点只需换个函数名。
Route<T> noSwipeRoute<T>({required WidgetBuilder builder, RouteSettings? settings}) =>
    appRoute<T>(builder: builder, gestures: false, settings: settings);
