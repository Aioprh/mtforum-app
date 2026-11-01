import '../data/models.dart';

/// 置顶回复与分页的去重。
///
/// Discuz 只在第 1 页额外插入一份置顶回复（`forum_viewthread.php` 里
/// `$_G['page'] === 1` 才查 `forum_poststick`），它原本所在的那一页
/// 仍会照常返回同一条楼层。所以「14 楼被置顶」时，第 1 页顶部会有一条
/// 带「置顶」标记的 14 楼，翻到第 2 页又会出现一条 14 楼。
///
/// 网页端第 1 页把置顶插进 `$postarr` 后靠 `$postlist[$post['pid']]` 去重，
/// 同一页里不会重复；跨页那份得由客户端自己收尾——把已经置顶展示过的
/// 楼层跳掉，其余楼层保持原有顺序和楼号，不做重编号。
class ThreadPaging {
  const ThreadPaging._();

  /// 一页结果里被站点标记为置顶的楼层 pid。
  static Set<int> pinnedPidsOf(Iterable<ForumPost> posts) =>
      posts.where((post) => post.isPinned).map((post) => post.pid).toSet();

  /// 去掉已经在前面展示过的置顶楼层，顺序与楼号都不动。
  ///
  /// 保留 `isPinned` 的那条：第 1 页顶部本来就是它，不能被自己过滤掉。
  static List<ForumPost> withoutPinnedDuplicates(
    Iterable<ForumPost> posts,
    Set<int> pinnedPids,
  ) {
    if (pinnedPids.isEmpty) return posts.toList();
    return posts
        .where((post) => post.isPinned || !pinnedPids.contains(post.pid))
        .toList();
  }
}
