import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../data/forum_repository.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/post_html_view.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';

/// 帖子详情：楼层流 + 分页加载 + 回复 / 收藏 / 分享。
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

  ThreadDetail? _detail;
  final List<ForumPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _favorited = false;
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
      final detail = await _repo.fetchThread(widget.tid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _posts
          ..clear()
          ..addAll(detail.posts);
        _page = 1;
        _hasMore = detail.hasMore;
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
        _posts.addAll(detail.posts.map((post) => ForumPost(
              pid: post.pid,
              author: post.author,
              avatar: post.avatar,
              time: post.time,
              html: post.html,
              floor: post.floor + offset,
              level: post.level,
              location: post.location,
              isOp: post.isOp,
              images: post.images,
            )));
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

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) {
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
    setState(() => _sending = true);
    try {
      final message = await _repo.reply(
        tid: widget.tid,
        fid: detail.fid,
        formhash: detail.formhash,
        message: text,
      );
      if (!mounted) return;
      _replyController.clear();
      _replyFocus.unfocus();
      _toast(message);
      await _load();
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _sending = false);
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
    await Clipboard.setData(ClipboardData(text: '${widget.title.isEmpty ? _detail?.title ?? '帖子' : widget.title}\n$_link'));
    _toast('帖子链接已复制');
  }

  Future<void> _openInBrowser() async {
    await launchUrl(Uri.parse(_link), mode: LaunchMode.externalApplication);
  }

  void _focusReply() {
    _replyFocus.requestFocus();
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

    return Scaffold(
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
      body: _buildBody(),
      bottomNavigationBar: _replyBar(),
    );
  }

  Widget _buildBody() {
    if (_loading && _posts.isEmpty) {
      return const SafeArea(top: false, child: FeedSkeleton(count: 3));
    }
    if (_error != null && _posts.isEmpty) {
      return SafeArea(
        top: false,
        child: ErrorView(message: _error!, onRetry: _load),
      );
    }
    if (_posts.isEmpty) {
      return SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            children: [
              const SizedBox(height: 80),
              EmptyView(text: _detail?.notice.isNotEmpty == true ? _detail!.notice : '该帖子暂时没有可显示的内容'),
            ],
          ),
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
          const SizedBox(height: 12),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ],
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
          ],
        ),
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

  Widget _replyBar() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 7, 8, 7),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: '收藏',
              onPressed: _toggleFavorite,
              icon: Icon(
                _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _favorited ? const Color(0xFFF5A524) : scheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _replyController,
                focusNode: _replyFocus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendReply(),
                decoration: const InputDecoration(
                  hintText: '写下你的回复…',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 7),
            IconButton.filled(
              tooltip: '发送',
              onPressed: _sending ? null : _sendReply,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}
