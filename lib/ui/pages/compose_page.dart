import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/emoji_panel.dart';
import 'login_page.dart';

/// 发布新主题：标题 / 正文 / 表情 / 图片 / @ / 插入 / 附件 / 高级选项 / 草稿。
class ComposePage extends StatefulWidget {
  const ComposePage({super.key, this.initialFid, this.initialBoardName});

  final int? initialFid;
  final String? initialBoardName;

  @override
  State<ComposePage> createState() => _ComposePageState();
}

enum _ComposePanel { emoji, mention, insert, attach, advanced }

class _DraftAttachment {
  _DraftAttachment({required this.name, required this.bytes, required this.image});

  final String name;
  final Uint8List bytes;
  final bool image;
  int? aid;
  bool uploading = false;
  String? error;
}

class _ComposePageState extends State<ComposePage> {
  static const String _draftSubject = 'mt_compose_draft_subject';
  static const String _draftMessage = 'mt_compose_draft_message';
  static const String _draftFidKey = 'mt_compose_draft_fid';
  static const String _draftAt = 'mt_compose_draft_at';

  final TextEditingController _subject = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _message = TextEditingController();
  final TextEditingController _mention = TextEditingController();
  final TextEditingController _linkUrl = TextEditingController();
  final TextEditingController _linkText = TextEditingController();
  final TextEditingController _mediaUrl = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _messageKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();
  final List<_DraftAttachment> _attachments = <_DraftAttachment>[];
  final List<TextEditingController> _pollOptions = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  List<ForumCategory> _categories = const [];
  bool _loadingBoards = true;
  bool _submitting = false;
  bool _uploading = false;
  bool _restoredDraft = false;
  bool _poll = false;
  bool _pollMultiple = false;
  int? _fid;
  int? _draftFid;
  String? _error;
  ComposeInfo? _info;
  _ComposePanel? _panel;
  String? _insertKind;

  bool _replyOnly = false;
  bool _orderDesc = false;
  bool _notify = true;
  bool _useSignature = true;

  final TextEditingController _readPerm = TextEditingController();
  final TextEditingController _price = TextEditingController();

  @override
  void initState() {
    super.initState();
    _messageFocus.addListener(_onMessageFocus);
    _init();
  }

  @override
  void dispose() {
    _subject.dispose();
    _tags.dispose();
    _message.dispose();
    _mention.dispose();
    _linkUrl.dispose();
    _linkText.dispose();
    _mediaUrl.dispose();
    _readPerm.dispose();
    _price.dispose();
    _messageFocus.dispose();
    _scroll.dispose();
    for (final controller in _pollOptions) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    await _restoreDraft();
    await _loadBoards();
    if (mounted && _restoredDraft) {
      _toast('已恢复上次保存的草稿');
    }
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final subject = prefs.getString(_draftSubject) ?? '';
    final message = prefs.getString(_draftMessage) ?? '';
    if (subject.trim().isEmpty && message.trim().isEmpty) return;
    final savedAt = prefs.getInt(_draftAt) ?? 0;
    if (savedAt > 0 && DateTime.now().millisecondsSinceEpoch - savedAt > 7 * 24 * 3600 * 1000) {
      return;
    }
    _subject.text = subject;
    _message.text = message;
    _draftFid = prefs.getInt(_draftFidKey);
    _restoredDraft = true;
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftSubject, _subject.text);
    await prefs.setString(_draftMessage, _message.text);
    await prefs.setInt(_draftAt, DateTime.now().millisecondsSinceEpoch);
    final fid = _fid;
    if (fid != null) await prefs.setInt(_draftFidKey, fid);
    _toast('草稿已保存，下次进入发帖页会自动恢复');
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftSubject);
    await prefs.remove(_draftMessage);
    await prefs.remove(_draftFidKey);
    await prefs.remove(_draftAt);
  }

  Future<void> _loadBoards() async {
    try {
      final value = await AppState.instance.boards();
      if (!mounted) return;
      var fid = _fid ?? _draftFid ?? widget.initialFid;
      final exists = fid != null && value.any((c) => c.boards.any((b) => b.fid == fid));
      if (!exists) {
        fid = value.isNotEmpty && value.first.boards.isNotEmpty ? value.first.boards.first.fid : null;
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
        _error = _messageOf(e);
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

  String _messageOf(Object error) => error is SiteException ? error.message : '操作失败，请稍后重试';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _ensureLogin() async {
    if (AppState.instance.isLoggedIn) return true;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    return ok == true && AppState.instance.isLoggedIn;
  }

  Future<ComposeInfo?> _ensureInfo() async {
    final cached = _info;
    if (cached != null && cached.formhash.isNotEmpty) return cached;
    final fid = _fid;
    if (fid == null) {
      setState(() => _error = '请选择要发布的版块');
      return null;
    }
    if (!await _ensureLogin()) return null;
    if (!mounted) return null;
    try {
      final value = await AppState.instance.repo.fetchComposeInfo(fid);
      if (!mounted) return null;
      setState(() => _info = value);
      return value;
    } catch (e) {
      if (!mounted) return null;
      setState(() => _error = _messageOf(e));
      _toast(_messageOf(e));
      return null;
    }
  }

  void _onBoardChanged(int? value) {
    if (value == null) return;
    setState(() {
      _fid = value;
      _info = null;
    });
  }

  void _onMessageFocus() {
    if (!_messageFocus.hasFocus) return;
    if (_panel != null) {
      setState(() => _panel = null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureMessageVisible());
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _ensureMessageVisible();
    });
  }

  /// 键盘弹出后把正文输入框滚动到可见区域，避免被输入法遮挡。
  void _ensureMessageVisible() {
    final ctx = _messageKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 220),
      alignment: 0.35,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  void _togglePanel(_ComposePanel panel) {
    FocusScope.of(context).unfocus();
    setState(() {
      _panel = _panel == panel ? null : panel;
      if (_panel != _ComposePanel.insert) _insertKind = null;
    });
  }

  Future<void> _pickImages() async {
    final info = await _ensureInfo();
    if (info == null) return;
    final picked = await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 78);
    if (picked.isEmpty) return;
    if (!mounted) return;
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final attachment = _DraftAttachment(name: file.name, bytes: bytes, image: true);
      setState(() => _attachments.add(attachment));
      await _upload(attachment, image: true);
    }
  }

  Future<void> _pickFiles() async {
    final info = await _ensureInfo();
    if (info == null) return;
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    if (!mounted) return;
    for (final file in files) {
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        _toast('${file.name} 读取失败');
        continue;
      }
      if (!mounted) return;
      if (bytes.length > 1024 * 1024) {
        _toast('${file.name} 超过 1MB，无法上传');
        continue;
      }
      final attachment = _DraftAttachment(name: file.name, bytes: bytes, image: false);
      setState(() => _attachments.add(attachment));
      await _upload(attachment, image: false);
    }
  }

  Future<void> _upload(_DraftAttachment attachment, {required bool image}) async {
    final info = _info;
    final fid = _fid;
    if (info == null || fid == null) return;
    setState(() {
      attachment.uploading = true;
      attachment.error = null;
      _uploading = true;
    });
    try {
      final aid = await AppState.instance.repo.uploadAttachment(
        bytes: attachment.bytes,
        filename: attachment.name,
        uploadHash: info.uploadHash,
        uid: info.uid,
        referer: AppConfig.uri('forum.php', {
          'mod': 'post',
          'action': 'newthread',
          'fid': '$fid',
          'mobile': '2',
        }).toString(),
        image: image,
      );
      if (!mounted) return;
      attachment.aid = aid;
      insertAtCursor(
        _message,
        image ? '\n[attachimg]$aid[/attachimg]\n' : '\n[attach]$aid[/attach]\n',
      );
      setState(() => attachment.uploading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        attachment.uploading = false;
        attachment.error = _messageOf(e);
      });
      _toast(_messageOf(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAttachment(_DraftAttachment attachment) {
    final aid = attachment.aid;
    if (aid != null) {
      final tag = attachment.image ? '[attachimg]$aid[/attachimg]' : '[attach]$aid[/attach]';
      _message.text = _message.text.replaceAll(tag, '');
    }
    setState(() => _attachments.remove(attachment));
  }

  void _insertMention() {
    final name = _mention.text.trim();
    if (name.isEmpty) {
      _toast('请输入要 @ 的用户名');
      return;
    }
    insertAtCursor(_message, '@$name ');
    _mention.clear();
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _insertLink() {
    final url = _linkUrl.text.trim();
    if (url.isEmpty) {
      _toast('请输入链接网址');
      return;
    }
    final text = _linkText.text.trim().isEmpty ? url : _linkText.text.trim();
    insertAtCursor(_message, '[url=$url]$text[/url]');
    _linkUrl.clear();
    _linkText.clear();
    _insertKind = null;
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _insertMedia(String kind) {
    final url = _mediaUrl.text.trim();
    if (url.isEmpty) {
      _toast('请输入链接地址');
      return;
    }
    final code = switch (kind) {
      'image' => '[img]$url[/img]',
      'audio' => '[audio]$url[/audio]',
      'video' => '[media=x,500,375]$url[/media]',
      'flash' => '[flash=480,400]$url[/flash]',
      _ => url,
    };
    insertAtCursor(_message, code);
    _mediaUrl.clear();
    _insertKind = null;
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _insertWrap(String tag) {
    insertWrapped(_message, '[$tag]', '[/$tag]');
    setState(() => _panel = null);
    _messageFocus.requestFocus();
  }

  void _addPollOption() {
    if (_pollOptions.length >= 10) {
      _toast('最多添加 10 个选项');
      return;
    }
    setState(() => _pollOptions.add(TextEditingController()));
  }

  void _removePollOption(int index) {
    if (_pollOptions.length <= 2) return;
    final controller = _pollOptions.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  List<String> get _pollTexts => [
        for (final controller in _pollOptions)
          if (controller.text.trim().isNotEmpty) controller.text.trim(),
      ];

  Future<void> _submit() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _panel = null);
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
    final options = _pollTexts;
    if (_poll && options.length < 2) {
      setState(() => _error = '投票至少需要两个选项');
      return;
    }
    if (!_poll && message.length < 4) {
      setState(() => _error = '正文内容太短');
      return;
    }
    final info = await _ensureInfo();
    if (info == null) return;
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
        formhash: info.formhash,
        attachmentIds: [
          for (final attachment in _attachments)
            if (attachment.aid != null) attachment.aid!,
        ],
        replyOnly: _replyOnly,
        orderDesc: _orderDesc,
        notify: _notify,
        useSignature: _useSignature,
        readPerm: _readPerm.text.trim(),
        price: _price.text.trim(),
        poll: _poll,
        pollOptions: options,
        pollMultiple: _pollMultiple,
        tags: _tags.text.trim(),
      );
      await _clearDraft();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageOf(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      // 自行处理键盘高度，保证底部输入区始终浮在输入法之上。
      resizeToAvoidBottomInset: false,
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
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: _content(scheme),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _toolbar(scheme),
                  _panelArea(),
                ],
              ),
            ),
            if (insets > 0) SizedBox(height: insets),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(ColorScheme scheme) {
    return [
      _modeTabs(scheme),
      const SizedBox(height: 12),
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
          onChanged: _onBoardChanged,
        ),
      const SizedBox(height: 14),
      TextField(
        controller: _subject,
        textInputAction: TextInputAction.next,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: '标题（必填）',
          hintText: '一句话说明你的主题',
          counterText: '',
          prefixIcon: Icon(Icons.title_rounded),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _tags,
        maxLength: 60,
        decoration: const InputDecoration(
          labelText: '主题标签（可选）',
          hintText: '多个标签用空格分隔',
          counterText: '',
          prefixIcon: Icon(Icons.sell_outlined),
        ),
      ),
      const SizedBox(height: 14),
      if (_poll) ...[
        _pollEditor(scheme),
        const SizedBox(height: 14),
      ],
      TextField(
        key: _messageKey,
        controller: _message,
        focusNode: _messageFocus,
        minLines: _poll ? 3 : 8,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: _poll
              ? '投票说明（可选）'
              : '想和大家分享点什么…\n\n支持 Discuz 常用 BBCode，可在下方工具栏插入表情、图片与链接。',
          alignLabelWithHint: true,
        ),
      ),
      if (_attachments.isNotEmpty) ...[
        const SizedBox(height: 14),
        _attachmentGrid(scheme),
      ],
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
        label: Text(_submitting ? '正在发布…' : '发表'),
      ),
      const SizedBox(height: 10),
      FilledButton.tonalIcon(
        onPressed: _submitting ? null : _saveDraft,
        icon: const Icon(Icons.save_outlined, size: 18),
        label: const Text('保存草稿'),
      ),
      const SizedBox(height: 14),
      Text(
        '请遵守 MT论坛版规，发布前确认内容与所选版块相符。',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
    ];
  }

  Widget _modeTabs(ColorScheme scheme) {
    Widget tab(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: 20,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: active ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55))),
      ),
      child: Row(
        children: [
          tab('发表帖子', !_poll, () => setState(() => _poll = false)),
          tab('发投票', _poll, () => setState(() => _poll = true)),
        ],
      ),
    );
  }

  Widget _pollEditor(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_vote_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('投票选项', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Text('${_pollOptions.length}/10', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
            ],
          ),
          for (var i = 0; i < _pollOptions.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pollOptions[i],
                      maxLength: 40,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: '选项 ${i + 1}',
                        counterText: '',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_pollOptions.length > 2)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '删除选项',
                      onPressed: () => _removePollOption(i),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: _addPollOption,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加选项'),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('允许多选', style: TextStyle(fontSize: 13.5)),
            value: _pollMultiple,
            onChanged: (value) => setState(() => _pollMultiple = value),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '至少填写 2 个选项，提交后生成投票主题。',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentGrid(ColorScheme scheme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final attachment in _attachments) _thumb(attachment, scheme),
        _addTile(scheme),
      ],
    );
  }

  Widget _thumb(_DraftAttachment attachment, ColorScheme scheme) {
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: attachment.image
                  ? Image.memory(
                      attachment.bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fileTile(scheme, Icons.broken_image_outlined),
                    )
                  : _fileTile(scheme, Icons.insert_drive_file_outlined),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
            ),
          ),
          if (attachment.uploading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)),
                child: const Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
              ),
            ),
          if (attachment.error != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Icon(Icons.error_outline_rounded, color: Colors.white, size: 20)),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: attachment.uploading ? null : () => _removeAttachment(attachment),
              child: const CircleAvatar(
                radius: 9,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close_rounded, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileTile(ColorScheme scheme, IconData icon) {
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Icon(icon, color: scheme.onSurfaceVariant, size: 26),
    );
  }

  Widget _addTile(ColorScheme scheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _uploading ? null : _pickImages,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(Icons.add_rounded, color: scheme.onSurfaceVariant, size: 30),
      ),
    );
  }

  Widget _toolbar(ColorScheme scheme) {
    const items = <(_ComposePanel, IconData, String)>[
      (_ComposePanel.emoji, Icons.sentiment_satisfied_alt_rounded, '表情'),
      (_ComposePanel.mention, Icons.alternate_email_rounded, '@朋友'),
      (_ComposePanel.insert, Icons.send_rounded, '插入'),
      (_ComposePanel.attach, Icons.attach_file_rounded, '附件'),
      (_ComposePanel.advanced, Icons.tune_rounded, '高级'),
    ];
    return Row(
      children: [
        for (final item in items)
          Expanded(
            child: InkWell(
              onTap: () => _togglePanel(item.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.$2,
                      size: 21,
                      color: _panel == item.$1 ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.$3,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _panel == item.$1 ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _panelArea() {
    return switch (_panel) {
      _ComposePanel.emoji => EmojiPanel(onSelected: (emoji) => insertAtCursor(_message, emoji)),
      _ComposePanel.mention => _mentionPanel(),
      _ComposePanel.insert => _insertPanel(),
      _ComposePanel.attach => _attachPanel(),
      _ComposePanel.advanced => _advancedPanel(),
      null => const SizedBox.shrink(),
    };
  }

  Widget _panelShell(ColorScheme scheme, Widget child) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: child,
      ),
    );
  }

  Widget _mentionPanel() {
    final scheme = Theme.of(context).colorScheme;
    return _panelShell(
      scheme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mention,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _insertMention(),
                  decoration: const InputDecoration(
                    hintText: '请输入用户名',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _insertMention,
                child: const Text('@添加'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '@朋友账号，就能提醒他来看帖子；也可以在正文中直接输入 @用户名。',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _insertPanel() {
    final scheme = Theme.of(context).colorScheme;
    const chips = <(String, String, String)>[
      ('link', '文字链接', 'url'),
      ('image', '网络图片', 'img'),
      ('audio', 'MP3 音乐', 'audio'),
      ('video', '网络视频', 'video'),
      ('flash', 'Flash', 'flash'),
      ('quote', '引用', 'quote'),
      ('code', '代码', 'code'),
      ('free', '免费信息', 'free'),
      ('hide', '隐藏内容', 'hide'),
    ];
    return _panelShell(
      scheme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in chips)
                ChoiceChip(
                  label: Text(
                    chip.$2,
                    style: TextStyle(
                      fontSize: 12,
                      color: _insertKind == chip.$1
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                  backgroundColor: scheme.surfaceContainerLow,
                  selectedColor: scheme.primaryContainer,
                  side: BorderSide(
                    color: _insertKind == chip.$1
                        ? scheme.primary.withValues(alpha: 0.55)
                        : scheme.outlineVariant.withValues(alpha: 0.75),
                  ),
                  selected: _insertKind == chip.$1,
                  onSelected: (_) {
                    if (chip.$3 != 'url' && chip.$3 != 'img' && chip.$3 != 'audio' &&
                        chip.$3 != 'video' && chip.$3 != 'flash') {
                      _insertWrap(chip.$3);
                      return;
                    }
                    setState(() {
                      _insertKind = chip.$1;
                      _mediaUrl.clear();
                    });
                  },
                ),
            ],
          ),
          if (_insertKind == 'link') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _linkUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '链接网址', isDense: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _linkText,
              decoration: const InputDecoration(labelText: '链接文字（可留空）', isDense: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _insertLink, child: const Text('插入')),
          ] else if (_insertKind != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _mediaUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '链接地址', isDense: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => _insertMedia(_insertKind!),
              child: const Text('插入'),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '插入的内容会以 BBCode 追加到正文光标处。',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _attachPanel() {
    final scheme = Theme.of(context).colorScheme;
    return _panelShell(
      scheme,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _uploading ? null : _pickFiles,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(_uploading ? '上传中…' : '上传文件'),
              ),
              const Spacer(),
              Text('大小限制：1MB', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '附件会以 [attach]…[/attach] 的形式插入正文；图片请点击正文下方的「+」从相册选择。',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _advancedPanel() {
    final scheme = Theme.of(context).colorScheme;
    return _panelShell(
      scheme,
      Column(
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('回帖仅作者可见', style: TextStyle(fontSize: 13.5)),
            value: _replyOnly,
            onChanged: (value) => setState(() => _replyOnly = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('回帖倒序排列', style: TextStyle(fontSize: 13.5)),
            value: _orderDesc,
            onChanged: (value) => setState(() => _orderDesc = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('接收回复通知', style: TextStyle(fontSize: 13.5)),
            value: _notify,
            onChanged: (value) => setState(() => _notify = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('使用个人签名', style: TextStyle(fontSize: 13.5)),
            value: _useSignature,
            onChanged: (value) => setState(() => _useSignature = value),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _readPerm,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '阅读权限',
                      hintText: '0 为不限制',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '售价（金币）',
                      hintText: '0 为免费',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
