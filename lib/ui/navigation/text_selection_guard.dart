import 'package:flutter/foundation.dart';

/// 「此刻有文本正在被选中」的全局标记。
///
/// 手机上看长帖子，长按选字之后手指是横向移动的 —— 和「右拖后退、左拖前进」
/// 完全是同一个手势。手势层如果不让路，就会一边拉选一边翻页。
/// 正文的 [SelectionArea] 在选中状态变化时上报，手势层据此放弃这一次拖动。
///
/// 用集合而不是布尔值：一页里可能有多个楼层各自挂着选择区，谁也不能在
/// 自己取消选择时把别人的状态一起清掉。
class TextSelectionGuard {
  const TextSelectionGuard._();

  static final Set<Object> _owners = <Object>{};

  static bool get selecting => _owners.isNotEmpty;

  /// [owner] 表示谁在选：一般直接传 State 实例，重复上报不会重复计数。
  static void setSelecting(Object owner, bool value) {
    if (value) {
      _owners.add(owner);
    } else {
      _owners.remove(owner);
    }
  }

  /// 页面销毁时清掉自己的记录，免得选着半截退出后手势一直失效。
  static void release(Object owner) => _owners.remove(owner);

  @visibleForTesting
  static void reset() => _owners.clear();
}
