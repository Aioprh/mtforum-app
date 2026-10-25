import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../data/forum_repository.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/post_html_view.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';

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
    _replyFocus.addListener(_onReplyFocus);
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

  void _onReplyFocus() {
    if (!_replyFocus.hasFocus) return;
    if (_showEmoji) setState(() => _showEmoji = false);
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await _repo.fetchThread(widget.tid);
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final detail = await _repo.fetchThread(widget.tid, page: _page + 1);
      if (!mounted) return;
      final offset = _page * AppConfig.postsPerPage;
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
    await Clipboard.setData(ClipboardData(
      text: '${widget.title.isEmpty ? _detail?.title ?? '帖子' : widget.title}\n$_link',
    ));
    _toast('帖子链接已复制');
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
          const SizedBox(height: 6),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ],
      ),
    );
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
                UserAvatar(url: post.avatar, name: post.author, size: 34),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.author.isEmpty ? '匿名' : post.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
                _floorAction(Icons.link_rounded, '复制楼层', () => _copyFloor(post), highlight: false),
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
