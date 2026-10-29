import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/offline_thread_cache.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../core/native_bridge.dart';
import '../../data/forum_repository.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/post_html_view.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'pm_page.dart';
import 'user_page.dart';

/// 帖子详情：楼层流 + 分页加载 + 点赞 / 收藏 / 回复 / 楼中楼。
class ThreadPage extends StatefulWidget {
  const ThreadPage({super.key, required this.tid, this.title = ''});

  final int tid;
  final String title;

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<int> _replyAttachments = <int>[];

  ThreadDetail? _detail;
  final List<ForumPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _uploading = false;
  bool _favorited = false;
  bool _liked = false;
  bool _disliked = false;
  bool _showEmoji = false;
  bool _onlyOp = false;
  bool _orderDesc = false;
  bool _voting = false;
  final Set<int> _pollSelected = <int>{};
  ForumPost? _replyTarget;
  bool _quoteTarget = false;
  int _likes = 0;
  int _dislikes = 0;
  String? _error;
  int _page = 1;
  bool _hasMore = false;

  ForumRepository get _repo => AppState.instance.repo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  String get _link => AppConfig.uri('thread-${widget.tid}-1-1.html').toString();

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await _repo.fetchThread(
        widget.tid,
        authorId: _onlyOp ? _opUid : null,
        orderDesc: _orderDesc,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _posts
          ..clear()
          ..addAll(detail.posts);
        _page = 1;
        _hasMore = detail.hasMore;
        _likes = detail.likes;
        _dislikes = detail.dislikes;
        _favorited = detail.favorited;
        _pollSelected.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  int get _opUid {
    final uid = _detail?.uid ?? 0;
    if (uid > 0) return uid;
    return _posts.isNotEmpty ? _posts.first.uid : 0;
  }

  Future<void> _setOnlyOp(bool value) async {
    setState(() {
      _onlyOp = value;
      _showEmoji = false;
    });
    await _load();
  }

  Future<void> _setOrderDesc(bool value) async {
    setState(() {
      _orderDesc = value;
      _showEmoji = false;
    });
    await _load();
  }

  Future<void> _loadMore() => _loadPage(_page + 1);

  Future<void> _loadPrevious() => _loadPage(_page - 1);

  /// 显式分页：每页显示站点返回的 10 条楼层，切页时替换当前列表，
  /// 不再滚动到底自动追加，避免不同页的楼层和评论混在一起。
  Future<void> _loadPage(int page) async {
    if (_loadingMore || page < 1 || (page > _page && !_hasMore)) return;
    setState(() => _loadingMore = true);
    try {
      final detail = await _repo.fetchThread(
        widget.tid,
        page: page,
        authorId: _onlyOp ? _opUid : null,
        orderDesc: _orderDesc,
      );
      if (!mounted) return;
      final offset = _orderDesc ? 0 : (page - 1) * AppConfig.postsPerPage;
      setState(() {
        _page = page;
        _posts
          ..clear()
          ..addAll(detail.posts.map((post) => post.copyWith(
            floor: post.isPinned ? post.floor : post.floor + offset,
          )));
        _hasMore = detail.hasMore;
        _loadingMore = false;
      });
      if (_scroll.hasClients) {
        await _scroll.animateTo(0, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(_message(e));
    }
  }

  String _message(Object error) => error is SiteException ? error.message : '加载失败，请稍后重试';

  Future<bool> _ensureLogin() async {
    if (AppState.instance.isLoggedIn) return true;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    return ok == true && AppState.instance.isLoggedIn;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------- 回复 / 楼中楼

  void _focusReply() {
    setState(() {
      _replyTarget = null;
      _quoteTarget = false;
    });
    _replyFocus.requestFocus();
  }

  void _startReply(ForumPost post) {
    setState(() {
      _replyTarget = post;
      _quoteTarget = false;
      _showEmoji = false;
    });
    _replyFocus.requestFocus();
  }

  void _startQuote(ForumPost post) {
    final plain = _plainText(post.html);
    if (plain.isNotEmpty) {
      insertAtCursor(
        _replyController,
        '[quote][size=2][url=forum.php?mod=redirect&goto=findpost&pid=${post.pid}&ptid=${widget.tid}]'
        '[color=#999999]${post.author} 发表于 ${post.time}[/color][/url][/size]\n$plain\n[/quote]\n',
      );
    }
    setState(() {
      _replyTarget = post;
      _quoteTarget = true;
      _showEmoji = false;
    });
    _replyFocus.requestFocus();
  }

  void _clearReplyTarget() {
    setState(() {
      _replyTarget = null;
      _quoteTarget = false;
    });
  }

  /// 楼中楼：在指定楼层下直接点评，走 Discuz 的 `action=comment`。
  Future<void> _openCommentSheet(ForumPost post, {String replyTo = ''}) async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null) return;
    if (!mounted) return;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CommentSheet(
        title: '点评 · ${post.floorLabel}',
        hint: replyTo.isEmpty ? '说点什么…' : '回复这条点评…',
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final message = await _repo.addComment(
        tid: widget.tid,
        pid: post.pid,
        message: text,
        formhash: detail.formhash,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty && _replyAttachments.isEmpty) {
      _toast('请输入回复内容');
      return;
    }
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('回复信息已失效，请下拉刷新后重试');
      return;
    }
    if (detail.fid == 0) {
      _toast('无法识别帖子所属版块');
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      final message = await _repo.reply(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        message: text,
        replyToPid: _replyTarget?.pid,
        quote: _quoteTarget,
        attachmentIds: List<int>.from(_replyAttachments),
      );
      if (!mounted) return;
      _replyController.clear();
      _replyAttachments.clear();
      _replyFocus.unfocus();
      setState(() {
        _replyTarget = null;
        _quoteTarget = false;
        _showEmoji = false;
      });
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachReplyImage() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    if (detail.uploadHash.isEmpty) {
      _toast('上传凭证已失效，请下拉刷新后重试');
      return;
    }
    final picked = await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 78);
    if (picked.isEmpty) return;
    if (!mounted) return;
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _uploading = true);
      try {
        final aid = await _repo.uploadAttachment(
          bytes: bytes,
          filename: file.name,
          uploadHash: detail.uploadHash,
          uid: detail.uid,
          referer: _link,
        );
        if (!mounted) return;
        _replyAttachments.add(aid);
        insertAtCursor(_replyController, '\n[attachimg]$aid[/attachimg]\n');
        _toast('图片已插入回复');
      } catch (e) {
        _toast(_message(e));
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    }
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _replyFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _showEmoji = true);
  }

  // ------------------------------------------------------------- 点赞 / 收藏

  Future<void> _toggleLike() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    final wasLiked = _liked;
    try {
      await _repo.recommend(
        tid: widget.tid,
        formhash: detail.formhash,
        up: true,
        cancel: wasLiked,
      );
      if (!mounted) return;
      setState(() {
        _liked = !wasLiked;
        _likes = (_likes + (wasLiked ? -1 : 1)).clamp(0, 1 << 31);
      });
      _toast(wasLiked ? '已取消点赞' : '点赞成功');
    } catch (e) {
      final message = _message(e);
      if (mounted && message.contains('已经赞过')) setState(() => _liked = true);
      _toast(message);
    }
  }

  Future<void> _toggleDislike() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    try {
      await _repo.recommend(tid: widget.tid, formhash: detail.formhash, up: false);
      if (!mounted) return;
      setState(() {
        if (!_disliked) _dislikes += 1;
        _disliked = true;
      });
      _toast('已踩');
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _toggleFavorite() async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('收藏信息已失效，请下拉刷新后重试');
      return;
    }
    try {
      final wasFavorited = _favorited;
      final message = await _repo.toggleFavorite(
        tid: widget.tid,
        formhash: detail.formhash,
        favorited: wasFavorited,
        href: wasFavorited ? detail.favoriteHref : '',
      );
      if (!mounted) return;
      setState(() => _favorited = !wasFavorited);
      _toast(message);
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _share() async {
    final title = widget.title.isEmpty ? _detail?.title ?? '帖子' : widget.title;
    final text = '$title\n$_link';
    final shared = await NativeBridge.shareText(text);
    if (shared) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('帖子链接已复制');
  }

  Future<void> _ratePost(ForumPost post) async {
    if (!await _ensureLogin()) return;
    if (_isMine(post)) {
      _toast('不能打赏自己的帖子');
      return;
    }
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('打赏信息已失效，请刷新后重试');
      return;
    }
    var options = RateOptions.fallback;
    try {
      options = await _repo.fetchRateOptions(tid: widget.tid, pid: post.pid);
    } catch (_) {
      // 读取失败时按好评 / 金币的常见范围兜底。
    }
    if (!mounted) return;
    if (options.notice.isNotEmpty) {
      _toast(options.notice);
      return;
    }
    if (options.fields.every((field) => field.ceiling <= 0)) {
      _toast('24 小时内可用的打赏额度已用完，请明天再试');
      return;
    }
    final result = await showModalBottomSheet<_RateResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RateSheet(
        floor: post.floorLabel,
        isOp: post.isOp,
        author: post.author,
        avatar: post.avatar,
        options: options,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final message = await _repo.rate(
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
        scores: result.scores,
        reason: result.reason,
        notify: result.notify,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  /// 踢帖：站点插件达到 5 票会自动送审核，需二次确认。
  Future<void> _kickThread() async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.kickToken.isEmpty) {
      _toast('当前页面没有踢帖入口');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('踢帖（${detail.kickVotes}/${detail.kickLimit}）'),
        content: Text('踢帖人数达到 ${detail.kickLimit} 人后主题会进入审核，恶意踢帖可能被处罚。确定要踢「${detail.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确定踢帖')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.kickThread(
        tid: widget.tid,
        token: detail.kickToken,
        formhash: detail.formhash,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _moderate(String action, String label, {int? pid}) async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('操作信息已失效，请刷新后重试');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'stickreply' ? '置顶回复' : '$label主题'),
        content: Text(action == 'stickreply'
            ? '确定要置顶第 ${_posts.firstWhere((p) => p.pid == pid, orElse: () => _posts.first).floor} 楼的回复吗？'
            : '确定要对「${detail.title}」执行$label操作吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.moderate(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        action: action,
        pid: pid,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  /// 主题作者可以尝试置顶自己在本主题中的回复；最终权限仍由论坛服务端校验。
  Future<void> _pinOwnReply(ForumPost post) async {
    if (post.isOp || !_isMine(post) || _posts.isEmpty || !_isMine(_posts.first)) {
      _toast('只能置顶自己主题中的自己的回复');
      return;
    }
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('置顶信息已失效，请刷新后重试');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('置顶我的回复'),
        content: Text('确定要将自己发布的第 ${post.floor} 楼回复置顶吗？如果论坛未开放此权限，服务端会返回原因。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('置顶')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.moderate(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        action: 'stickreply',
        pid: post.pid,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _openPm(ForumPost post) async {
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PmPage(uid: post.uid, name: post.author),
    ));
  }

  Future<void> _openInBrowser() async {
    await launchUrl(Uri.parse(_link), mode: LaunchMode.externalApplication);
  }

  void _copyFloor(ForumPost post) {
    final url = AppConfig.uri('forum.php', {
      'mod': 'redirect',
      'goto': 'findpost',
      'pid': '${post.pid}',
    }).toString();
    Clipboard.setData(ClipboardData(text: url));
    _toast('楼层链接已复制');
  }

  bool _isMine(ForumPost post) {
    final uid = AppState.instance.profile?.uid ?? 0;
    return post.uid > 0 && uid > 0 && post.uid == uid;
  }

  /// 只有称号 / 等级为版主（或管理员）时才显示管理类菜单。
  bool get _isModerator {
    final profile = AppState.instance.profile;
    if (profile == null) return false;
    final title = '${profile.group} ${profile.level}';
    return title.contains('版主') || title.contains('管理员');
  }

  void _openUser(int uid, String name) {
    if (uid <= 0) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserPage(uid: uid, name: name)));
  }

  Future<void> _handleFloorMenu(ForumPost post, String value) async {
    switch (value) {
      case 'copy':
        _copyFloor(post);
      case 'report':
        await _report(post);
      case 'rate':
        await _ratePost(post);
      case 'pm':
        await _openPm(post);
      case 'edit':
        await _editPost(post);
      case 'delete':
        await _deletePost(post);
      case 'stick':
        await _moderate('stickreply', '置顶回复', pid: post.pid);
      case 'pinOwnReply':
        await _pinOwnReply(post);
      case 'digest':
        await _moderate('digest', '精华');
      case 'close':
        await _moderate('close', '关闭');
      case 'warn':
        await _moderate('warn', '警告');
    }
  }

  Future<void> _report(ForumPost post) async {
    if (!await _ensureLogin()) return;
    final detail = _detail;
    if (detail == null) return;
    if (!mounted) return;
    final result = await showModalBottomSheet<(int, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReportSheet(floor: post.floorLabel),
    );
    if (result == null || !mounted) return;
    try {
      final message = await _repo.report(
        fid: detail.fid,
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
        reason: result.$1,
        message: result.$2,
      );
      _toast(message);
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _editPost(ForumPost post) async {
    final detail = _detail;
    if (detail == null) return;
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => _EditPostPage(
          fid: detail.fid,
          tid: widget.tid,
          pid: post.pid,
          formhash: detail.formhash,
          subject: post.isOp ? detail.title : 'Re: ${detail.title}',
          message: _stripEditNotice(_plainText(post.html)),
          isOp: post.isOp,
        ),
      ),
    );
    if (result == true && mounted) {
      _toast('已保存修改');
      await _load();
    } else if (result == 'deleted' && mounted) {
      await _load();
    }
  }

  Future<void> _deletePost(ForumPost post) async {
    final detail = _detail;
    if (detail == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除${post.isOp ? '整篇主题' : '第 ${post.floor} 楼的回复'}吗？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await _repo.deletePost(
        fid: detail.fid,
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
      );
      _toast(message);
      if (post.isOp && mounted) {
        Navigator.of(context).maybePop();
        return;
      }
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _cacheForOffline() async {
    final current = _detail;
    if (current == null || _posts.isEmpty) {
      _toast('帖子内容尚未加载完成，暂时无法缓存');
      return;
    }
    _toast('正在缓存整篇帖子，评论和图片较多时可能需要一些时间');
    try {
      final first = await _repo.fetchThread(widget.tid, page: 1);
      final allPosts = <ForumPost>[...first.posts];
      var hasMore = first.hasMore;
      var page = 1;
      // Fetch every page, independently of the current "only OP" and sort filters.
      while (hasMore && page < 500) {
        page++;
        final next = await _repo.fetchThread(widget.tid, page: page);
        final offset = (page - 1) * AppConfig.postsPerPage;
        allPosts.addAll(next.posts.map((post) => post.copyWith(floor: post.isPinned ? post.floor : post.floor + offset)));
        hasMore = next.hasMore;
        if (next.posts.isEmpty && hasMore) break;
      }
      await OfflineThreadCache.instance.save(
        tid: widget.tid,
        title: first.title,
        boardName: first.boardName,
        author: first.author,
        time: first.time,
        views: first.views,
        replies: first.replies,
        posts: allPosts,
      );
      if (mounted) {
        final suffix = hasMore ? '（达到分页安全上限，已保存前 $page 页）' : '';
        _toast('已缓存整篇帖子：${allPosts.length} 条内容$suffix');
      }
    } catch (error) {
      if (mounted) _toast('缓存失败：${_message(error)}');
    }
  }

  void _handleMenu(String value) {
    switch (value) {
      case 'favorite':
        _toggleFavorite();
      case 'offlineCache':
        _cacheForOffline();
      case 'copy':
        _share();
      case 'browser':
        _openInBrowser();
      case 'refresh':
        _load();
      case 'onlyOp':
        _setOnlyOp(!_onlyOp);
      case 'order':
        _setOrderDesc(!_orderDesc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = detail?.title.isNotEmpty == true
        ? detail!.title
        : (widget.title.isEmpty ? '帖子详情' : widget.title);
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      // 输入框由页面自行避让键盘，避免被输入法遮挡。
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '分享链接',
            onPressed: _share,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenu,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'favorite',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_favorited ? Icons.star_rounded : Icons.star_outline_rounded),
                  title: Text(_favorited ? '已收藏' : '收藏主题'),
                ),
              ),
              const PopupMenuItem(
                value: 'offlineCache',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_for_offline_outlined),
                  title: Text('缓存帖子供离线阅读'),
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded),
                  title: Text('复制链接'),
                ),
              ),
              const PopupMenuItem(
                value: 'browser',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.open_in_browser_rounded),
                  title: Text('在浏览器打开'),
                ),
              ),
              PopupMenuItem(
                value: 'onlyOp',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_onlyOp ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                  title: const Text('只看楼主'),
                ),
              ),
              PopupMenuItem(
                value: 'order',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_orderDesc ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                  title: const Text('倒序浏览'),
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('刷新'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildBody()),
            _composer(),
            if (insets > 0) SizedBox(height: insets),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _posts.isEmpty) {
      return const FeedSkeleton(count: 3);
    }
    if (_error != null && _posts.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          children: [
            const SizedBox(height: 80),
            EmptyView(text: _detail?.notice.isNotEmpty == true ? _detail!.notice : '该帖子暂时没有可显示的内容'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: 1 + _posts.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _header();
          final postIndex = index - 1;
          if (postIndex < _posts.length) {
            final post = _posts[postIndex];
            if (postIndex == 1 && !_onlyOp) {
              final scheme = Theme.of(context).colorScheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 5, 4, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Text('评论区', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Text('${_detail?.replies ?? (_posts.length - 1)} 条回复',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        Icon(Icons.forum_outlined, size: 17, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: _postCard(post),
                  ),
                ],
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _postCard(post),
            );
          }
          return _footer();
        },
      ),
    );
  }

  Widget _header() {
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detail.title,
            style: const TextStyle(fontSize: 20.5, fontWeight: FontWeight.w800, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (detail.boardName.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detail.boardName,
                    style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              _meta(Icons.person_outline_rounded, detail.author.isEmpty ? '未知作者' : detail.author),
              _meta(Icons.schedule_rounded, detail.time),
              _meta(Icons.chat_bubble_outline_rounded, '${detail.replies} 回复'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionButton(
                icon: _liked ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
                label: _likes > 0 ? '赞 $_likes' : '赞',
                active: _liked,
                onTap: _toggleLike,
              ),
              _actionButton(
                icon: _disliked ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
                label: _dislikes > 0 ? '踩 $_dislikes' : '踩',
                active: _disliked,
                onTap: _toggleDislike,
              ),
              _actionButton(
                icon: _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                label: _favorited ? '已收藏' : '收藏',
                active: _favorited,
                onTap: _toggleFavorite,
              ),
              _actionButton(
                icon: Icons.ios_share_rounded,
                label: '分享',
                active: false,
                onTap: _share,
              ),
            ],
          ),
          if (detail.poll != null) ...[
            const SizedBox(height: 10),
            _pollCard(detail.poll!),
          ],
          const SizedBox(height: 6),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ],
      ),
    );
  }

  /// 投票卡片：显示选项与票数，未投票时可直接勾选提交。
  Widget _pollCard(Poll poll) {
    final scheme = Theme.of(context).colorScheme;
    final votable = !poll.expired && poll.options.every((option) => option.id > 0);
    final maxVotes = poll.options.fold<int>(1, (max, option) => option.votes > max ? option.votes : max);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_vote_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  poll.multiple ? '投票 · 多选' : '投票 · 单选',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                ),
              ),
              Text(
                poll.total > 0 ? '${poll.total} 人参与' : (poll.expired ? '已结束' : '暂无投票'),
                style: TextStyle(fontSize: 10.5, color: scheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final option in poll.options)
            InkWell(
              onTap: votable && option.id > 0
                  ? () => setState(() {
                        if (poll.multiple) {
                          if (!_pollSelected.remove(option.id)) _pollSelected.add(option.id);
                        } else {
                          _pollSelected
                            ..clear()
                            ..add(option.id);
                        }
                      })
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      _pollSelected.contains(option.id)
                          ? (poll.multiple ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                          : (poll.multiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_unchecked_rounded),
                      size: 17,
                      color: _pollSelected.contains(option.id) ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(option.text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
                          if (option.votes > 0) ...[
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: option.votes / (maxVotes == 0 ? 1 : maxVotes),
                                minHeight: 4,
                                backgroundColor: scheme.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      option.votes > 0 ? '${option.votes} 票' : '',
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          if (votable && !poll.voted) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: _voting ? null : _vote,
                style: FilledButton.styleFrom(minimumSize: const Size(88, 32), padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: _voting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('提交投票', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _vote() async {
    final detail = _detail;
    if (detail == null) return;
    if (!await _ensureLogin()) return;
    if (_pollSelected.isEmpty) {
      _toast('请先选择投票选项');
      return;
    }
    setState(() => _voting = true);
    try {
      final message = await _repo.votePoll(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        ids: _pollSelected.toList(),
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: active ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: scheme.outline),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _postCard(ForumPost post) {
    final scheme = Theme.of(context).colorScheme;
    final targeted = _replyTarget?.pid == post.pid;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      elevation: 0,
      color: post.isOp
          ? scheme.primary.withValues(alpha: 0.045)
          : scheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(post.isOp ? 16 : 12),
        side: BorderSide(
          color: targeted
              ? scheme.primary.withValues(alpha: 0.75)
              : post.isOp
                  ? scheme.primary.withValues(alpha: 0.38)
                  : scheme.outlineVariant.withValues(alpha: 0.55),
          width: targeted ? 1.5 : post.isOp ? 1.1 : 0.6,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, post.isOp ? 14 : 10, 14, post.isOp ? 10 : 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => _openUser(post.uid, post.author),
                  child: UserAvatar(url: post.avatar, name: post.author, size: 34),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => _openUser(post.uid, post.author),
                              child: Text(
                                post.author.isEmpty ? '匿名' : post.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          if (post.level.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: scheme.tertiary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                post.level,
                                style: TextStyle(fontSize: 9.5, color: scheme.tertiary, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [post.time, if (post.location.isNotEmpty) post.location].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: post.isOp
                        ? scheme.primary.withValues(alpha: 0.1)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    post.isOp ? '主题正文' : post.floorLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: post.isOp ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            PostHtmlView(html: post.html, images: post.images, onReply: _focusReply),
            if (post.isOp && !_isMine(post)) ...[
              const SizedBox(height: 12),
              _opActions(post),
            ],
            if (post.rates.isNotEmpty || post.rateSummary.isNotEmpty) ...[
              const SizedBox(height: 10),
              _rateLog(post),
            ],
            if (post.comments.isNotEmpty) ...[
              const SizedBox(height: 10),
              _commentList(post),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                _floorAction(Icons.reply_rounded, '回复', () => _startReply(post), highlight: false),
                _floorAction(Icons.format_quote_rounded, '引用', () => _startQuote(post), highlight: targeted && _quoteTarget),
                _floorAction(Icons.chat_bubble_outline_rounded, '点评', () => _openCommentSheet(post), highlight: false),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: '更多操作',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(Icons.more_horiz_rounded, color: Theme.of(context).colorScheme.outline),
                  onSelected: (value) => _handleFloorMenu(post, value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.link_rounded, size: 20),
                        title: Text('复制楼层'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'report',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.flag_outlined, size: 20),
                        title: Text('举报'),
                      ),
                    ),
                    if (!_isMine(post))
                      PopupMenuItem(
                        value: 'rate',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.volunteer_activism_outlined, size: 20),
                          title: Text(post.isOp ? '赞赏' : '打赏'),
                        ),
                      ),
                    if (!_isMine(post) && post.uid > 0)
                      const PopupMenuItem(
                        value: 'pm',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.mail_outline_rounded, size: 20),
                          title: Text('发消息'),
                        ),
                      ),
                    if (_isModerator) ...[
                      const PopupMenuItem(
                        value: 'stick',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.vertical_align_top_rounded, size: 20),
                          title: Text('置顶回复'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'digest',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.workspace_premium_outlined, size: 20),
                          title: Text('设精华'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'close',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.lock_outline_rounded, size: 20),
                          title: Text('关闭主题'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'warn',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.gavel_rounded, size: 20),
                          title: Text('警告'),
                        ),
                      ),
                    ],
                    if (!post.isOp && _isMine(post) && _posts.isNotEmpty && _isMine(_posts.first))
                      const PopupMenuItem(
                        value: 'pinOwnReply',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.push_pin_outlined, size: 20),
                          title: Text('置顶我的回复'),
                        ),
                      ),
                    if (_isMine(post)) ...[
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined, size: 20),
                          title: Text('编辑'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline_rounded, size: 20),
                          title: Text('删除'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 楼主楼层底部的「赞赏 / 踢帖」按钮，与站点移动模板保持一致。
  Widget _opActions(ForumPost post) {
    final detail = _detail;
    final kickLabel = detail == null || detail.kickToken.isEmpty
        ? ''
        : '踢帖(${detail.kickVotes}/${detail.kickLimit})';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: () => _ratePost(post),
          icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
          label: const Text('赞赏'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE3A008),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        if (kickLabel.isNotEmpty) ...[
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _kickThread,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: Text(kickLabel),
          ),
        ],
      ],
    );
  }

  /// 楼层打赏记录：`N 人参与了打赏` + 明细。
  Widget _rateLog(ForumPost post) {
    final scheme = Theme.of(context).colorScheme;
    final title = post.rateSummary.isNotEmpty ? post.rateSummary : '${post.rates.length} 人参与了打赏';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.tertiary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volunteer_activism_outlined, size: 13, color: scheme.tertiary),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.tertiary),
              ),
            ],
          ),
          for (final record in post.rates.take(8))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(children: [
                  if (record.score.isNotEmpty)
                    TextSpan(
                      text: '${record.score} ',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.tertiary),
                    ),
                  TextSpan(
                    text: record.username.isEmpty ? '匿名' : record.username,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  if (record.reason.isNotEmpty)
                    TextSpan(
                      text: '：${record.reason}',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _floorAction(IconData icon, String label, VoidCallback onTap, {required bool highlight}) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11.5, color: color)),
          ],
        ),
      ),
    );
  }

  /// 回复某条点评：Discuz 的点评本身不是独立帖子，没有可用于 reppost 的 pid。
  /// 将点评内容引用到正式回复编辑器，并关联其所属楼层，避免 action=comment
  /// 将内容再次提交为普通点评。
  void _startCommentReply(ForumPost post, ForumComment comment) {
    final author = comment.author.isEmpty ? '匿名' : comment.author;
    final quotedText = comment.text.trim();
    final timeLabel = comment.time.isEmpty ? '' : ' 发表于 ${comment.time}';
    insertAtCursor(
      _replyController,
      '[quote][size=2][color=#999999]回复 $author$timeLabel[/color][/size]\\n'
      '$quotedText\\n[/quote]\\n',
    );
    setState(() {
      _replyTarget = post;
      _quoteTarget = true;
      _showEmoji = false;
    });
    _replyFocus.requestFocus();
  }

  /// 楼中楼点评列表：点击任意一条可针对该条点评发起正式回复。
  Widget _commentList(ForumPost post) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '楼中楼 · ${post.comments.length}',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: scheme.outline),
          ),
          const SizedBox(height: 4),
          for (final comment in post.comments)
            InkWell(
              onTap: () => _startCommentReply(post, comment),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: comment.author.isEmpty ? '匿名' : comment.author,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.primary),
                    ),
                    TextSpan(
                      text: comment.time.isEmpty ? '：' : '（${comment.time}）：',
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                    TextSpan(
                      text: comment.text,
                      style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurface),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer() {
    final scheme = Theme.of(context).colorScheme;
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _page > 1 ? _loadPrevious : null,
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('上一页'),
          ),
          const SizedBox(width: 16),
          Text('第 $_page 页', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _hasMore ? _loadMore : null,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: const Text('下一页'),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTarget != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
              child: Row(
                children: [
                  Icon(
                    _quoteTarget ? Icons.format_quote_rounded : Icons.reply_rounded,
                    size: 14,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${_quoteTarget ? '引用' : '回复'} @${_replyTarget!.author} · ${_replyTarget!.floorLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: scheme.primary),
                    ),
                  ),
                  IconButton(
                    tooltip: '取消',
                    visualDensity: VisualDensity.compact,
                    onPressed: _clearReplyTarget,
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 7, 8, 7),
            child: Row(
              children: [
                IconButton(
                  tooltip: '表情',
                  onPressed: _toggleEmoji,
                  icon: Icon(
                    _showEmoji ? Icons.keyboard_alt_outlined : Icons.sentiment_satisfied_alt_rounded,
                    color: _showEmoji ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    focusNode: _replyFocus,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _replyTarget == null ? '写下你的回复…' : '回复 @${_replyTarget!.author}…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '插入图片',
                  onPressed: _uploading ? null : _attachReplyImage,
                  icon: _uploading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined, size: 20),
                ),
                const SizedBox(width: 2),
                IconButton.filled(
                  tooltip: '发送',
                  onPressed: _sending ? null : _sendReply,
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 19),
                ),
              ],
            ),
          ),
          if (_showEmoji)
            EmojiPanel(
              height: 220,
              onSelected: (emoji) => insertAtCursor(_replyController, emoji),
            ),
        ],
      ),
    );
  }

  /// 仅移除 Discuz 自动插入的编辑记录，保留帖子正文。
/// 不按标记位置截断整段文本：部分模板会把编辑记录放在正文开头，
/// 截断会导致编辑器里的正文被清空。
String _stripEditNotice(String text) {
  var result = text;
  result = result.replaceAll(
    RegExp(r'本帖最后由\s*.+?\s+于\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}\s+编辑', dotAll: true),
    '',
  );
  result = result.replaceAll(RegExp(r'帖子编辑\s*'), '');
  return result.trim();
}

String _plainText(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(div|p|li|blockquote)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 楼中楼点评输入面板：自带键盘避让，返回输入的文本。
class _CommentSheet extends StatefulWidget {
  const _CommentSheet({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<_CommentSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // BottomSheet 在部分屏幕/字体缩放配置下会按子组件的最小宽度测量；
    // 显式约束为屏幕宽度，避免提示文案被挤成逐字竖排。
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              maxLength: 200,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: widget.hint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点评会直接显示在该楼层下方',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _send,
                child: const Text('发送'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 编辑主题或回复。
class _EditPostPage extends StatefulWidget {
  const _EditPostPage({
    required this.fid,
    required this.tid,
    required this.pid,
    required this.formhash,
    required this.subject,
    required this.message,
    required this.isOp,
  });

  final int fid;
  final int tid;
  final int pid;
  final String formhash;
  final String subject;
  final String message;
  final bool isOp;

  @override
  State<_EditPostPage> createState() => _EditPostPageState();
}

enum _EditPanel { emoji, mention, insert, attach }

class _EditAttachment {
  _EditAttachment({required this.name, required this.image});
  final String name;
  final bool image;
  int? aid;
  bool uploading = false;
  String? error;
}

class _EditPostPageState extends State<_EditPostPage> {
  late final TextEditingController _subject = TextEditingController(text: widget.subject);
  late final TextEditingController _message = TextEditingController(text: widget.message);
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  final ImagePicker _imagePicker = ImagePicker();
  _EditPanel? _panel;
  String? _editMediaKind;
  final TextEditingController _mentionController = TextEditingController();
  final TextEditingController _insertUrlController = TextEditingController();
  final TextEditingController _insertLabelController = TextEditingController();
  List<FriendItem> _friends = const <FriendItem>[];
  bool _friendsLoading = false;
  String? _friendsError;
  final List<_EditAttachment> _attachments = <_EditAttachment>[];

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _mentionController.dispose();
    _insertUrlController.dispose();
    _insertLabelController.dispose();
    super.dispose();
  }

  void _insertAtCursor(String value) {
    final selection = _message.selection;
    final start = selection.isValid ? selection.start : _message.text.length;
    final end = selection.isValid ? selection.end : _message.text.length;
    final text = _message.text.replaceRange(start, end, value);
    _message.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  void _toggleEditPanel(_EditPanel panel) {
    FocusScope.of(context).unfocus();
    setState(() { _panel = _panel == panel ? null : panel; _editMediaKind = null; });
    if (panel == _EditPanel.mention && _panel == panel) _loadEditFriends();
  }

  Future<void> _loadEditFriends({bool force = false}) async {
    if (_friendsLoading || (!force && _friends.isNotEmpty)) return;
    if (!AppState.instance.isLoggedIn) {
      setState(() => _friendsError = '登录后可读取论坛好友列表');
      return;
    }
    setState(() { _friendsLoading = true; _friendsError = null; });
    try {
      final value = await AppState.instance.repo.fetchFriends();
      if (!mounted) return;
      setState(() { _friends = value; _friendsError = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() => _friendsError = e is SiteException ? e.message : '好友列表加载失败');
    } finally {
      if (mounted) setState(() => _friendsLoading = false);
    }
  }

  Future<void> _uploadFiles({required bool image}) async {
    if (_uploading || _saving) return;
    try {
      final info = await AppState.instance.repo.fetchComposeInfo(widget.fid);
      if (!mounted) return;
      if (image) {
        final picked = await _imagePicker.pickMultiImage(maxWidth: 1600, imageQuality: 78);
        for (final file in picked) {
          if (!mounted) return;
          final item = _EditAttachment(name: file.name, image: true);
          setState(() { _attachments.add(item); _uploading = true; _error = null; });
          try {
            final aid = await AppState.instance.repo.uploadAttachment(
              bytes: await file.readAsBytes(), filename: file.name,
              uploadHash: info.uploadHash, uid: info.uid,
              referer: AppConfig.uri('forum.php', {'mod':'post','action':'edit','fid':'${widget.fid}','tid':'${widget.tid}','pid':'${widget.pid}','mobile':'2'}).toString(),
              image: true,
            );
            if (!mounted) return;
            item.aid = aid;
            _insertAtCursor('\\n[attachimg]$aid[/attachimg]\\n');
          } catch (e) {
            if (!mounted) return;
            item.error = e is SiteException ? e.message : '图片上传失败';
            setState(() => _error = item.error);
          } finally {
            if (mounted) setState(() { item.uploading = false; _uploading = false; });
          }
        }
      } else {
        // Use the same FilePicker wrapper/API as the publish-post page.
        // This project exposes FilePicker.pickFiles() returning a file list.
        final files = await FilePicker.pickFiles(type: FileType.any);
        if (files.isEmpty) return;
        for (final file in files) {
          if (!mounted) return;
          final item = _EditAttachment(name: file.name, image: false);
          setState(() { _attachments.add(item); _uploading = true; _error = null; });
          try {
            final bytes = await file.readAsBytes();
            final aid = await AppState.instance.repo.uploadAttachment(
              bytes: bytes, filename: file.name,
              uploadHash: info.uploadHash, uid: info.uid,
              referer: AppConfig.uri('forum.php', {'mod':'post','action':'edit','fid':'${widget.fid}','tid':'${widget.tid}','pid':'${widget.pid}','mobile':'2'}).toString(),
              image: false,
            );
            if (!mounted) return;
            item.aid = aid;
            _insertAtCursor('\\n[attach]$aid[/attach]\\n');
          } catch (e) {
            if (!mounted) return;
            item.error = e is SiteException ? e.message : '附件上传失败';
            setState(() => _error = item.error);
          } finally {
            if (mounted) setState(() { item.uploading = false; _uploading = false; });
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is SiteException ? e.message : '上传失败，请重试');
    }
  }

  void _insertEditMention([String? username]) {
    final name = (username ?? _mentionController.text).trim();
    if (name.isEmpty) { setState(() => _error = '请输入要 @ 的用户名'); return; }
    _insertAtCursor('@$name ');
    _mentionController.clear();
    setState(() => _panel = null);
  }

  void _insertEditTag(String tag) {
    _wrapTag(tag);
    setState(() => _panel = null);
  }

  Future<void> _insertEditLink() async {
    final url = _insertUrlController.text.trim();
    final label = _insertLabelController.text.trim();
    if (url.isEmpty) { setState(() => _error = '请输入链接网址'); return; }
    _insertAtCursor('[url=$url]${label.isEmpty ? url : label}[/url]');
    _insertUrlController.clear(); _insertLabelController.clear();
    setState(() => _panel = null);
  }

  Future<void> _insertEditMedia(String kind) async {
    final url = _insertUrlController.text.trim();
    if (url.isEmpty) { setState(() => _error = '请输入链接地址'); return; }
    final tag = switch (kind) {
      'img' => '[img]$url[/img]',
      'audio' => '[audio]$url[/audio]',
      'video' => '[media=x,500,375]$url[/media]',
      'flash' => '[flash=480,400]$url[/flash]',
      _ => url,
    };
    _insertAtCursor(tag);
    _insertUrlController.clear();
    setState(() => _panel = null);
  }

  void _wrapTag(String tag) {
    final selection = _message.selection;
    final start = selection.isValid ? selection.start : _message.text.length;
    final end = selection.isValid ? selection.end : _message.text.length;
    final selected = start < end ? _message.text.substring(start, end) : '';
    final open = '[$tag]';
    final close = '[/$tag]';
    final value = '$open$selected$close';
    _message.value = TextEditingValue(
      text: _message.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + open.length + selected.length),
    );
  }

  Future<void> _delete() async {
    if (_saving || _uploading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除确认'),
        content: Text(widget.isOp ? '确定删除整篇主题吗？删除后不可恢复。' : '确定删除自己的这条回复吗？删除后不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      final message = await AppState.instance.repo.deletePost(
        fid: widget.fid,
        tid: widget.tid,
        pid: widget.pid,
        formhash: widget.formhash,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop('deleted');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is SiteException ? e.message : '删除失败，请稍后重试';
      });
    }
  }

  Future<void> _save() async {
    final subject = widget.isOp ? _subject.text.trim() : widget.subject;
    final message = _message.text.trim();
    if (widget.isOp && subject.isEmpty) {
      setState(() => _error = '标题不能为空');
      return;
    }
    if (message.isEmpty) {
      setState(() => _error = '内容不能为空');
      return;
    }
    setState(() {
      _panel = null;
      _saving = true;
      _error = null;
    });
    try {
      await AppState.instance.repo.editPost(
        fid: widget.fid,
        tid: widget.tid,
        pid: widget.pid,
        subject: subject,
        message: message,
        formhash: widget.formhash,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is SiteException ? e.message : '保存失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBusy = _saving || _uploading;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(widget.isOp ? '编辑主题' : '编辑回复'),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: isBusy ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_saving ? '保存中' : '保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          children: [
            if (widget.isOp) ...[
              Text('主题标题', style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 8),
              TextField(
                controller: _subject,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: '请输入主题标题',
                  counterText: '',
                  prefixIcon: const Icon(Icons.title_rounded),
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: scheme.primary, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            Row(
              children: [
                Expanded(
                  child: Text('正文内容', style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
                ),
                Text(
                  '支持图片、链接与 BBCode',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                      border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65))),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.start,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _editorTool(Icons.sentiment_satisfied_alt_rounded, '表情', () => _toggleEditPanel(_EditPanel.emoji)),
                        _editorTool(Icons.alternate_email_rounded, '@朋友', () => _toggleEditPanel(_EditPanel.mention)),
                        _editorTool(Icons.send_rounded, '插入', () => _toggleEditPanel(_EditPanel.insert)),
                        _editorTool(Icons.attach_file_rounded, '附件', () => _toggleEditPanel(_EditPanel.attach)),
                        _editorTool(Icons.add_photo_alternate_outlined, '上传图片', _uploading ? null : () => _uploadFiles(image: true)),
                        _editorTool(Icons.format_bold_rounded, '加粗', () => _wrapTag('b')),
                        _editorTool(Icons.format_italic_rounded, '斜体', () => _wrapTag('i')),
                        _editorTool(Icons.format_quote_rounded, '引用', () => _wrapTag('quote')),
                        _editorTool(Icons.code_rounded, '代码', () => _wrapTag('code')),
                      ],
                    ),
                  ),
                  if (_panel != null) _editPanelContent(scheme),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: TextField(
                      controller: _message,
                      minLines: 12,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15.5, height: 1.65),
                      decoration: InputDecoration(
                        hintText: '在这里编辑正文…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_uploading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 2),
              const SizedBox(height: 4),
              Text('正在上传图片…', style: TextStyle(fontSize: 12, color: scheme.primary)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(fontSize: 12.5, color: scheme.error))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55))),
          ),
          child: Row(
            children: [
              if (!widget.isOp) ...[
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: isBusy ? null : _delete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: const Text('删除'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: widget.isOp ? 1 : 2,
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(_saving ? '正在保存修改…' : '保存修改', style: const TextStyle(fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editPanelContent(ColorScheme scheme) {
    Widget shell(Widget child) => Container(
      constraints: const BoxConstraints(maxHeight: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65))),
      ),
      child: SingleChildScrollView(child: child),
    );
    switch (_panel!) {
      case _EditPanel.emoji:
        return EmojiPanel(onSelected: (emoji) => _insertAtCursor(_emojiInsertion(emoji)));
      case _EditPanel.mention:
        final key = _mentionController.text.trim().toLowerCase();
        final friends = _friends.where((f) => key.isEmpty || f.username.toLowerCase().contains(key)).take(12);
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(controller: _mentionController, onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: '搜索好友或输入用户名', isDense: true, prefixIcon: Icon(Icons.search), border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _insertEditMention, child: const Text('@添加')),
          ]),
          Row(children: [
            Expanded(child: Text(_friendsError ?? (_friendsLoading ? '正在加载好友…' : '选择好友可插入 @用户名，也可手动输入。'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
            IconButton(onPressed: _friendsLoading ? null : () => _loadEditFriends(force: true), icon: const Icon(Icons.refresh)),
          ]),
          if (_friendsLoading) const LinearProgressIndicator(),
          for (final friend in friends) ListTile(dense: true, title: Text(friend.username),
            leading: const Icon(Icons.alternate_email), onTap: () => _insertEditMention(friend.username)),
        ]));
      case _EditPanel.insert:
        const chips = <(String, String, String)>[
          ('url', '文字链接', 'url'), ('img', '网络图片', 'img'),
          ('audio', 'MP3 音乐', 'audio'), ('video', '网络视频', 'video'),
          ('flash', 'Flash', 'flash'), ('quote', '引用', 'quote'),
          ('code', '代码', 'code'), ('b', '加粗', 'b'), ('i', '斜体', 'i'),
          ('free', '免费信息', 'free'), ('hide', '隐藏内容', 'hide'),
        ];
        final isLink = _editMediaKind == 'url';
        final isMedia = const {'img', 'audio', 'video', 'flash'}.contains(_editMediaKind);
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final chip in chips)
              ChoiceChip(
                label: Text(chip.$2, style: TextStyle(fontSize: 12,
                  color: _editMediaKind == chip.$1 ? scheme.onPrimaryContainer : scheme.onSurface)),
                backgroundColor: scheme.surface,
                selectedColor: scheme.primaryContainer,
                side: BorderSide(color: _editMediaKind == chip.$1
                  ? scheme.primary.withValues(alpha: 0.65)
                  : scheme.outlineVariant.withValues(alpha: 0.8)),
                selected: _editMediaKind == chip.$1,
                onSelected: (_) {
                  if (const {'quote', 'code', 'b', 'i', 'free', 'hide'}.contains(chip.$1)) {
                    _insertEditTag(chip.$3);
                    return;
                  }
                  setState(() {
                    _editMediaKind = chip.$1;
                    _insertUrlController.clear();
                    _insertLabelController.clear();
                  });
                },
              ),
          ]),
          if (isLink || isMedia) ...[
            const SizedBox(height: 12),
            TextField(controller: _insertUrlController, keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: isLink ? '链接网址' : '链接 / 媒体地址',
                hintText: 'https://', isDense: true, border: const OutlineInputBorder())),
            if (isLink) ...[
              const SizedBox(height: 10),
              TextField(controller: _insertLabelController,
                decoration: const InputDecoration(labelText: '链接文字（可留空）', isDense: true, border: OutlineInputBorder())),
            ],
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: isLink ? _insertEditLink : () => _insertEditMedia(_editMediaKind!),
              icon: const Icon(Icons.add_link_rounded),
              label: Text(isLink ? '插入链接' : '插入媒体内容'))),
          ] else
            Padding(padding: const EdgeInsets.only(top: 10),
              child: Text('选择“文字链接”或媒体类型后，填写地址并点击插入；格式标签会直接包裹选中的正文。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
        ]));
      case _EditPanel.attach:
        return shell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: _uploading ? null : () => _uploadFiles(image: false),
            icon: const Icon(Icons.attach_file), label: Text(_uploading ? '正在上传…' : '添加文件 / 选择附件'))),
          Text('支持多选文件；格式及大小由论坛附件规则决定。上传成功后会在光标处插入附件标记。',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          for (final item in _attachments) ListTile(dense: true,
            leading: Icon(item.error != null ? Icons.error_outline : item.uploading ? Icons.cloud_upload_outlined : item.image ? Icons.image_outlined : Icons.insert_drive_file_outlined),
            title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.error ?? (item.uploading ? '上传中' : item.aid == null ? '待上传' : '已上传 · aid ${item.aid}')),
            trailing: IconButton(tooltip: '移除附件', onPressed: item.uploading ? null : () {
              final aid = item.aid;
              if (aid != null) {
                final tag = item.image ? '[attachimg]$aid[/attachimg]' : '[attach]$aid[/attach]';
                _message.text = _message.text.replaceAll(tag, '');
                _message.selection = TextSelection.collapsed(offset: _message.text.length);
              }
              setState(() => _attachments.remove(item));
            }, icon: const Icon(Icons.close_rounded, size: 18))),
        ]));
    }
  }

  String _emojiInsertion(String emoji) => emoji;

  Widget _editorTool(IconData icon, String label, VoidCallback? onPressed) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: (_saving || _uploading) ? null : onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: (_saving || _uploading) ? scheme.outline : scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: (_saving || _uploading) ? scheme.outline : scheme.onSurfaceVariant,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 举报面板。
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.floor});

  final String floor;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const List<String> _reasons = ['广告垃圾', '违规内容', '重复发帖', '恶意灌水', '其他'];

  final TextEditingController _controller = TextEditingController();
  int _reason = 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '举报 ${widget.floor}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          for (var i = 0; i < _reasons.length; i++)
            InkWell(
              onTap: () => setState(() => _reason = i + 1),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      _reason == i + 1 ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      size: 17,
                      color: _reason == i + 1 ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Text(_reasons[i], style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            maxLength: 120,
            decoration: const InputDecoration(
              hintText: '补充说明（可选）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text('举报将由版主处理', style: TextStyle(fontSize: 11, color: scheme.outline)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((_reason, _controller.text.trim())),
                child: const Text('提交举报'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 打赏结果：勾选的积分项、理由与是否通知作者。
class _RateResult {
  const _RateResult({required this.scores, this.reason = '', this.notify = false});

  final Map<int, int> scores;
  final String reason;
  final bool notify;
}

/// 打赏面板：对齐站点移动模板（头像 + 昵称 + 好评 / 金币 + 理由 + 通知作者）。
class _RateSheet extends StatefulWidget {
  const _RateSheet({
    required this.floor,
    required this.isOp,
    required this.author,
    required this.avatar,
    required this.options,
  });

  final String floor;
  final bool isOp;
  final String author;
  final String avatar;
  final RateOptions options;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  final TextEditingController _reason = TextEditingController();
  final Map<int, int> _scores = <int, int>{};
  bool _notify = false;

  @override
  void initState() {
    super.initState();
    for (final field in widget.options.fields) {
      _scores[field.id] = 0;
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int get _total => _scores.values.fold(0, (sum, value) => sum + value);

  void _submit() {
    if (_total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择打赏积分')),
      );
      return;
    }
    final scores = <int, int>{
      for (final entry in _scores.entries)
        if (entry.value != 0) entry.key: entry.value,
    };
    Navigator.of(context).pop(
      _RateResult(
        scores: scores,
        reason: _reason.text.trim(),
        notify: _notify,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, size: 20, color: scheme.outline),
              ),
            ),
            UserAvatar(url: widget.avatar, name: widget.author, size: 54),
            const SizedBox(height: 8),
            Text(
              widget.author.isEmpty ? '匿名' : widget.author,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              widget.isOp ? '搬砖不容易，打赏一下楼主吧' : '打赏一下${widget.floor}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            for (final field in widget.options.fields) _fieldRow(field, scheme),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _reason,
                minLines: 1,
                maxLines: 3,
                maxLength: 100,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '说两句鼓励一下吧…',
                  counterText: '',
                  isDense: true,
                  border: UnderlineInputBorder(),
                ),
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('通知作者', style: TextStyle(fontSize: 14)),
              value: _notify,
              onChanged: (value) => setState(() => _notify = value),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5A5A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  child: Text(
                    widget.isOp ? '赞赏' : '打赏',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(RateField field, ColorScheme scheme) {
    final ceiling = field.ceiling;
    final exhausted = ceiling <= 0;
    var start = field.min <= 0 ? field.min : 0;
    if (start > ceiling) start = 0;
    final values = <int>{0};
    if (!exhausted) {
      if (field.presets.isNotEmpty) {
        values.addAll(field.presets.where((score) => score >= start && score <= ceiling));
      } else {
        for (var score = start; score <= ceiling; score++) {
          values.add(score);
        }
      }
    }
    final options = values.toList()..sort();
    final current = _scores[field.id] ?? 0;
    final value = options.contains(current) ? current : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      child: Row(
        children: [
          Text(field.label, style: const TextStyle(fontSize: 14.5)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: value,
                isDense: true,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: scheme.outline),
                style: TextStyle(
                  fontSize: 15,
                  color: exhausted ? scheme.outline : scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                items: [
                  for (final score in options)
                    DropdownMenuItem<int>(value: score, child: Text('$score')),
                ],
                onChanged: exhausted
                    ? null
                    : (score) => setState(() => _scores[field.id] = score ?? 0),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            exhausted ? '已用完' : '剩 ${field.left}',
            style: TextStyle(
              fontSize: 10.5,
              color: exhausted ? scheme.error : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
