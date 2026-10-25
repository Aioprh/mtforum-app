import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
    _scroll.addListener(_onScroll);
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

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 420) {
      _loadMore();
    }
  }

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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final detail = await _repo.fetchThread(
        widget.tid,
        page: _page + 1,
        authorId: _onlyOp ? _opUid : null,
        orderDesc: _orderDesc,
      );
      if (!mounted) return;
      final offset = _orderDesc ? 0 : _page * AppConfig.postsPerPage;
      setState(() {
        _page += 1;
        _posts.addAll(detail.posts.map((post) => post.copyWith(floor: post.floor + offset)));
        _hasMore = detail.hasMore;
        _loadingMore = false;
      });
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
        hint: replyTo.isEmpty ? '说点什么…' : '回复 @$replyTo…',
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
    try {
      await _repo.recommend(tid: widget.tid, formhash: detail.formhash, up: true);
      if (!mounted) return;
      setState(() {
        if (!_liked) _likes += 1;
        _liked = true;
      });
      _toast('点赞成功');
    } catch (e) {
      _toast(_message(e));
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
      final message = await _repo.addFavorite(tid: widget.tid, formhash: detail.formhash);
      if (!mounted) return;
      setState(() => _favorited = true);
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
    final detail = _detail;
    if (detail == null || detail.formhash.isEmpty) {
      _toast('评分信息已失效，请刷新后重试');
      return;
    }
    if (!mounted) return;
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _RateDialog(floor: post.floorLabel),
    );
    if (result == null || !mounted) return;
    try {
      final message = await _repo.rate(
        tid: widget.tid,
        pid: post.pid,
        formhash: detail.formhash,
        score: result.$1,
        reason: result.$2,
      );
      if (!mounted) return;
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    }
  }

  Future<void> _moderate(String action, String label) async {
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
        title: Text('$label主题'),
        content: Text('确定要对「${detail.title}」执行$label操作吗？'),
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
        await _moderate('stickreply', '置顶');
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
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EditPostPage(
          fid: detail.fid,
          tid: widget.tid,
          pid: post.pid,
          formhash: detail.formhash,
          subject: post.isOp ? detail.title : 'Re: ${detail.title}',
          message: _plainText(post.html),
          isOp: post.isOp,
        ),
      ),
    );
    if (ok == true && mounted) {
      _toast('已保存修改');
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

  void _handleMenu(String value) {
    switch (value) {
      case 'favorite':
        _toggleFavorite();
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
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: _postCard(_posts[postIndex]),
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
      shape: targeted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 1.4),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
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
                    post.floorLabel,
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
            if (post.comments.isNotEmpty) ...[
              const SizedBox(height: 10),
              _commentList(post),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                _floorAction(Icons.reply_rounded, '回复', () => _startReply(post), highlight: targeted && !_quoteTarget),
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
                    const PopupMenuItem(
                      value: 'rate',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.star_half_rounded, size: 20),
                        title: Text('评分'),
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
                    const PopupMenuItem(
                      value: 'stick',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.vertical_align_top_rounded, size: 20),
                        title: Text('置顶（版主）'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'digest',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.workspace_premium_outlined, size: 20),
                        title: Text('设精华（版主）'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'close',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.lock_outline_rounded, size: 20),
                        title: Text('关闭主题（版主）'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'warn',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.gavel_rounded, size: 20),
                        title: Text('警告（版主）'),
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

  /// 楼中楼点评列表：点击任意一条即可继续回复该楼。
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
              onTap: () => _openCommentSheet(post, replyTo: comment.author),
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
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton.icon(
            onPressed: _loadMore,
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            label: const Text('加载更多楼层'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text('— 已经到底啦 —', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '点评会直接显示在该楼层下方',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
              FilledButton(onPressed: _send, child: const Text('发送')),
            ],
          ),
        ],
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

class _EditPostPageState extends State<_EditPostPage> {
  late final TextEditingController _subject = TextEditingController(text: widget.subject);
  late final TextEditingController _message = TextEditingController(text: widget.message);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOp ? '编辑主题' : '编辑回复'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (widget.isOp) ...[
              TextField(
                controller: _subject,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: '标题',
                  counterText: '',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _message,
              minLines: 10,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: '内容',
                alignLabelWithHint: true,
                hintText: '支持 Discuz BBCode',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 12.5, color: scheme.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.done_rounded, size: 18),
              label: Text(_saving ? '正在保存…' : '保存修改'),
            ),
          ],
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

/// 评分弹窗：选择分值并填写理由。
class _RateDialog extends StatefulWidget {
  const _RateDialog({required this.floor});

  final String floor;

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  final TextEditingController _controller = TextEditingController();
  int _score = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('评分 ${widget.floor}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final score in const [1, 2, 3, 4, 5, 6, 8, 10])
                ChoiceChip(
                  label: Text('$score 分'),
                  selected: _score == score,
                  onSelected: (_) => setState(() => _score = score),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '评分理由（可选）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '评分会消耗相应积分，请谨慎操作。',
            style: TextStyle(fontSize: 11.5, color: scheme.outline),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((_score, _controller.text.trim())),
          child: const Text('提交评分'),
        ),
      ],
    );
  }
}
