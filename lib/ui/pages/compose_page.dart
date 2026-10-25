import 'package:flutter/material.dart';

import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'login_page.dart';

/// 发布新主题。
class ComposePage extends StatefulWidget {
  const ComposePage({super.key, this.initialFid, this.initialBoardName});

  final int? initialFid;
  final String? initialBoardName;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();

  List<ForumCategory> _categories = const [];
  bool _loadingBoards = true;
  bool _submitting = false;
  int? _fid;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBoards();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadBoards() async {
    try {
      final value = await AppState.instance.boards();
      if (!mounted) return;
      var fid = _fid;
      if (fid == null) {
        final preset = widget.initialFid;
        final exists = preset != null && value.any((c) => c.boards.any((b) => b.fid == preset));
        fid = exists ? preset : (value.isNotEmpty && value.first.boards.isNotEmpty ? value.first.boards.first.fid : null);
      }
      setState(() {
        _categories = value;
        _fid = fid;
        _loadingBoards = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBoards = false;
        _error = e is SiteException ? e.message : '版块加载失败，请稍后重试';
      });
    }
  }

  List<(String, int)> get _options {
    final options = <(String, int)>[];
    for (final category in _categories) {
      for (final board in category.boards) {
        options.add(('${category.name} / ${board.name}', board.fid));
      }
    }
    return options;
  }

  Future<bool> _ensureLogin() async {
    if (AppState.instance.isLoggedIn) return true;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    return ok == true && AppState.instance.isLoggedIn;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    final fid = _fid;
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (fid == null) {
      setState(() => _error = '请选择要发布的版块');
      return;
    }
    if (subject.isEmpty) {
      setState(() => _error = '请填写标题');
      return;
    }
    if (message.length < 4) {
      setState(() => _error = '正文内容太短');
      return;
    }
    if (!await _ensureLogin()) return;
    if (!mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await AppState.instance.repo.createThread(
        fid: fid,
        subject: subject,
        message: message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is SiteException ? e.message : '发布失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialBoardName == null ? '发帖' : '发帖 · ${widget.initialBoardName}'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('发布', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            if (_loadingBoards)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_options.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _fid,
                decoration: const InputDecoration(
                  labelText: '发布到',
                  prefixIcon: Icon(Icons.dashboard_outlined),
                ),
                items: [
                  for (final option in _options)
                    DropdownMenuItem(
                      value: option.$2,
                      child: Text(option.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _fid = value),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _subject,
              textInputAction: TextInputAction.next,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '一句话说明你的主题',
                counterText: '',
                prefixIcon: Icon(Icons.title_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              minLines: 12,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '正文内容…\n\n支持论坛常用格式，提交后将按纯文本发布。',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(fontSize: 12.5, height: 1.5, color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(_submitting ? '正在发布…' : '发布主题'),
            ),
            const SizedBox(height: 14),
            Text(
              '请遵守 MT论坛版规，发布前确认内容与所选版块相符。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
