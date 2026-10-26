import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/state_views.dart';
import '../widgets/user_avatar.dart';
import 'login_page.dart';
import 'user_page.dart';

/// 私信对话：与某个用户的来往消息，可直接回复。
class PmChatPage extends StatefulWidget {
  const PmChatPage({super.key, required this.uid, this.name = ''});

  final int uid;
  final String name;

  @override
  State<PmChatPage> createState() => _PmChatPageState();
}

class _PmChatPageState extends State<PmChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<PmMessage> _messages = [];

  String _formhash = '';
  String _peer = '';
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _peer = widget.name;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AppState.instance.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = null;
        _messages.clear();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (messages, formhash, peer) = await AppState.instance.repo.fetchPmMessages(
        widget.uid,
        myUid: AppState.instance.profile?.uid ?? 0,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _formhash = formhash;
        if (peer.isNotEmpty) _peer = peer;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is SiteException ? e.message : '加载私信失败，请稍后重试';
      });
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (ok == true) await _load();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      var hash = _formhash;
      if (hash.isEmpty) {
        final info = await AppState.instance.repo.fetchUserProfile(widget.uid);
        hash = info.$2;
      }
      if (hash.isEmpty) throw SiteException('发送凭证已失效，请返回后重试');
      final tip = await AppState.instance.repo.sendPm(
        uid: widget.uid,
        formhash: hash,
        message: text,
      );
      if (!mounted) return;
      _input.clear();
      setState(() {
        _formhash = hash;
        _sending = false;
        _messages.add(PmMessage(
          text: text,
          author: AppState.instance.profile?.username ?? '我',
          uid: AppState.instance.profile?.uid ?? 0,
          time: '刚刚',
          mine: true,
        ));
      });
      _scrollToBottom();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tip)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is SiteException ? e.message : '发送失败，请稍后重试')),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _openPeer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => UserPage(uid: widget.uid, name: _peer),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_peer.isEmpty ? '私信' : _peer, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '查看主页',
            onPressed: _openPeer,
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !AppState.instance.isLoggedIn
            ? _loginHint(scheme)
            : Column(
                children: [
                  Expanded(child: _messageArea(scheme)),
                  _composer(scheme),
                ],
              ),
      ),
    );
  }

  Widget _messageArea(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_messages.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: const [SizedBox(height: 100), EmptyView(text: '还没有私信往来', icon: Icons.mail_outline_rounded)],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
        itemCount: _messages.length,
        itemBuilder: (context, index) => _bubble(scheme, _messages[index]),
      ),
    );
  }

  Widget _bubble(ColorScheme scheme, PmMessage message) {
    final mine = message.mine;
    final text = Text(
      message.text,
      style: TextStyle(fontSize: 13.5, height: 1.45, color: mine ? scheme.onPrimary : scheme.onSurface),
    );
    final time = message.time.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message.time,
              style: TextStyle(fontSize: 9.5, color: scheme.outline),
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            UserAvatar(url: '', name: _peer, size: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!mine && _peer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(_peer, style: TextStyle(fontSize: 10, color: scheme.outline)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: mine ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(mine ? 16 : 4),
                      bottomRight: Radius.circular(mine ? 4 : 16),
                    ),
                    border: Border.all(
                      color: mine ? Colors.transparent : scheme.outlineVariant.withValues(alpha: 0.45),
                    ),
                  ),
                  child: text,
                ),
                if (time != null) time,
              ],
            ),
          ),
          if (mine) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _composer(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '输入私信内容…',
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: '发送',
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 19),
          ),
        ],
      ),
    );
  }

  Widget _loginHint(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mail_outline_rounded, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text('登录后查看私信', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton(onPressed: _openLogin, child: const Text('立即登录')),
        ],
      ),
    );
  }
}
