import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'emoji_panel.dart';
import 'glass_dialog.dart';
import 'glass_controls.dart';
import 'site_form_dialog.dart';
import 'thread_glass.dart';

/// 私信输入栏。
///
/// 对齐网页版私信编辑器（`seditor.js`）的那排工具：加粗、颜色、链接、引用、
/// 代码、官方表情。插入的都是 BBCode，发送后由站点转成 HTML，和网页端发出去
/// 的消息完全一样。
class PmComposer extends StatefulWidget {
  const PmComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onEmojiChanged,
    this.showEmoji = false,
    this.sending = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<bool> onEmojiChanged;
  final bool showEmoji;
  final bool sending;

  @override
  State<PmComposer> createState() => _PmComposerState();
}

class _PmComposerState extends State<PmComposer> {
  final FocusNode _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant PmComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _onTextChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  /// 面板开着时点输入框，说明想打字了，把面板收起让键盘上来。
  void _onFocusChanged() {
    if (_focus.hasFocus && widget.showEmoji) widget.onEmojiChanged(false);
  }

  void _toggleEmoji() {
    if (widget.showEmoji) {
      widget.onEmojiChanged(false);
      _focus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onEmojiChanged(true);
  }

  void _insert(String text, {bool focus = true}) {
    insertAtCursor(widget.controller, text);
    if (focus) _focus.requestFocus();
  }

  void _wrap(String open, String close) {
    insertWrapped(widget.controller, open, close);
    _focus.requestFocus();
  }

  Future<void> _insertLink() async {
    FocusScope.of(context).unfocus();
    final values = await showSiteFormDialog(
      context,
      title: '插入链接',
      description: '和网页版私信一样，链接会以 BBCode 插到光标处。',
      confirmText: '插入',
      fields: const <MagicFormField>[
        MagicFormField(name: 'url', label: '链接网址', value: 'https://'),
        MagicFormField(name: 'text', label: '链接文字（可留空）'),
      ],
    );
    if (values == null || !mounted) return;
    var url = (values['url'] ?? '').trim();
    if (url.isEmpty || url == 'https://') {
      _toast('请填写链接网址');
      return;
    }
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(url)) {
      url = 'https://$url';
    }
    final label = (values['text'] ?? '').trim();
    _insert('[url=$url]${label.isEmpty ? url : label}[/url]');
  }

  Future<void> _pickColor() async {
    FocusScope.of(context).unfocus();
    final color = await showGlassDialog<String>(
      context: context,
      builder: (_) => const _PmColorDialog(),
    );
    if (color == null || !mounted) return;
    _wrap('[color=$color]', '[/color]');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassBackdrop(
      showBorder: false,
      opacityScale: 0.92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: ThreadGlass.borderColor(context), width: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _toolbar(scheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: GlassField(
                      controller: widget.controller,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      hintText: '输入私信内容…',
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: widget.sending || !_hasText ? null : widget.onSend,
                    icon: widget.sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 19),
                  ),
                ],
              ),
            ),
            if (widget.showEmoji) ...<Widget>[
              Divider(
                height: 0.6,
                thickness: 0.6,
                indent: 14,
                endIndent: 14,
                color: ThreadGlass.borderColor(context),
              ),
              EmojiPanel(
                height: 214,
                onSelected: (emoji) => _insert(emoji, focus: false),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolbar(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: <Widget>[
          _tool(
            scheme,
            widget.showEmoji
                ? Icons.keyboard_alt_outlined
                : Icons.sentiment_satisfied_alt_rounded,
            widget.showEmoji ? '收起表情' : '官方表情',
            _toggleEmoji,
            active: widget.showEmoji,
          ),
          const SizedBox(width: 2),
          _divider(scheme),
          const SizedBox(width: 2),
          _tool(scheme, Icons.format_bold_rounded, '加粗', () => _wrap('[b]', '[/b]')),
          _tool(scheme, Icons.format_color_text_rounded, '文字颜色', _pickColor),
          _tool(scheme, Icons.link_rounded, '插入链接', _insertLink),
          _tool(scheme, Icons.format_quote_rounded, '引用', () => _wrap('[quote]', '[/quote]')),
          _tool(scheme, Icons.code_rounded, '代码', () => _wrap('[code]', '[/code]')),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) {
    return Container(
      width: 0.6,
      height: 18,
      color: scheme.outlineVariant.withValues(alpha: 0.55),
    );
  }

  Widget _tool(
    ColorScheme scheme,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 19,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 官方私信编辑器的取色板：只给固定颜色，不让人手填任意色值。
class _PmColorDialog extends StatelessWidget {
  const _PmColorDialog();

  static const List<Color> _colors = <Color>[
    Color(0xFF000000),
    Color(0xFF444444),
    Color(0xFF808080),
    Color(0xFFC0C0C0),
    Color(0xFFFFFFFF),
    Color(0xFFD32F2F),
    Color(0xFFF57C00),
    Color(0xFFFBC02D),
    Color(0xFF388E3C),
    Color(0xFF0097A7),
    Color(0xFF1976D2),
    Color(0xFF7B1FA2),
    Color(0xFFC2185B),
    Color(0xFF8D6E63),
    Color(0xFF00695C),
    Color(0xFF283593),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassDialog(
      title: const Text('文字颜色'),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: <Widget>[
          for (final color in _colors)
            InkWell(
              onTap: () => Navigator.of(context).pop(_hexOf(color)),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color.computeLuminance() > 0.9
                        ? scheme.outlineVariant
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  static String _hexOf(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0')}';
  }
}
