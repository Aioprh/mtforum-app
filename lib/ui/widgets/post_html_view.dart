import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import '../../core/app_config.dart';
import '../../core/http_session.dart';
import '../pages/board_threads_page.dart';
import '../pages/image_viewer_page.dart';
import '../pages/internal_browser_page.dart';
import '../pages/thread_page.dart';
import 'smart_image.dart';

/// 将论坛帖子的 HTML 内容解析为原生 Flutter 组件。
class PostHtmlView extends StatefulWidget {
  const PostHtmlView({super.key, required this.html, this.images = const <String>[], this.onReply});

  final String html;
  final List<String> images;
  final VoidCallback? onReply;

  @override
  State<PostHtmlView> createState() => _PostHtmlViewState();
}

class _PostHtmlViewState extends State<PostHtmlView> {
  final List<GestureRecognizer> _recognizers = <GestureRecognizer>[];
  List<Widget>? _cache;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disposeRecognizers();
    _cache = null;
  }

  @override
  void didUpdateWidget(covariant PostHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _disposeRecognizers();
      _cache = null;
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  bool _isBlockTag(String tag) => const {
        'div', 'p', 'section', 'article', 'blockquote', 'pre', 'ul', 'ol',
        'table', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'iframe', 'video',
        'audio', 'center',
      }.contains(tag);

  bool _isSmiley(dom.Element img) {
    final src = (img.attributes['src'] ?? img.attributes['comiis_loadimages'] ?? '').toLowerCase();
    if (src.contains('/smiley/') || src.contains('smiley') || src.contains('smilies')) return true;
    final width = double.tryParse(img.attributes['width'] ?? '');
    final height = double.tryParse(img.attributes['height'] ?? '');
    if (width == null || height == null) return false;
    return width > 0 && height > 0 && width <= 32 && height <= 32;
  }

  String _imageUrl(dom.Element img) {
    final raw = (img.attributes['comiis_loadimages'] ??
            img.attributes['data-src'] ??
            img.attributes['data-original'] ??
            img.attributes['file'] ??
            img.attributes['src'] ??
            img.attributes['longdesc'] ??
            '')
        .trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('file://')) return raw;
    if (raw.contains('none.png') || raw.contains('imageloading.gif') || raw.contains('noavatar')) {
      final candidates = <String>[
        img.attributes['data-src']?.trim() ?? '',
        img.attributes['data-original']?.trim() ?? '',
        img.attributes['file']?.trim() ?? '',
        img.attributes['comiis_loadimages']?.trim() ?? '',
        img.attributes['longdesc']?.trim() ?? '',
      ];
      for (final candidate in candidates) {
        if (candidate.isNotEmpty && !candidate.contains('none.png') && !candidate.contains('imageloading.gif') && !candidate.contains('noavatar')) {
          return AppConfig.uri(candidate).toString();
        }
      }
    }
    return AppConfig.uri(raw).toString();
  }

  List<Widget> _blocks(BuildContext context, List<dom.Node> nodes) {
    final widgets = <Widget>[];
    final inline = <InlineSpan>[];

    void flush() {
      if (inline.isEmpty) return;
      final spans = List<InlineSpan>.from(inline);
      inline.clear();
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SelectableText.rich(
          TextSpan(children: spans),
          style: TextStyle(
            fontSize: 15.5,
            height: 1.62,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ));
    }

    for (final node in nodes) {
      if (node is dom.Text) {
        final text = _cleanInline(node.text);
        if (text.trim().isEmpty) continue;
        inline.addAll(_linkifyText(context, text, TextStyle(
          fontSize: 15.5,
          height: 1.62,
          color: Theme.of(context).colorScheme.onSurface,
        )));
        continue;
      }
      if (node is! dom.Element) continue;

      final tag = node.localName ?? '';
      if (tag == 'br') {
        if (inline.isNotEmpty) inline.add(const TextSpan(text: '\n'));
        continue;
      }
      // 附件图片常被 <a> 包裹，整块渲染，避免被当成行内元素丢掉。
      if (tag == 'a' && node.querySelector('img') != null) {
        final imgs = node.querySelectorAll('img');
        flush();
        for (final img in imgs) {
          if (_isSmiley(img)) continue;
          final image = _imageBlock(context, img);
          if (image != null) widgets.add(image);
        }
        final text = node.text.trim();
        if (text.isNotEmpty) inline.add(TextSpan(text: text));
        continue;
      }
      if (tag == 'img') {
        if (_isSmiley(node)) {
          final src = _imageUrl(node);
          if (src.isNotEmpty) {
            inline.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Image.network(
                  src,
                  width: 22,
                  height: 22,
                  headers: _headers(),
                  errorBuilder: (_, __, ___) => const SizedBox(width: 22, height: 22),
                ),
              ),
            ));
          }
        } else {
          flush();
          final image = _imageBlock(context, node);
          if (image != null) widgets.add(image);
        }
        continue;
      }

      // 引用块要优先于普通容器处理：站点皮肤常把 [quote] 渲染成
      // div.quote（没有 blockquote），不拦截就会退化成一整段正文。
      if (_isQuoteContainer(tag, node.classes) || _looksLikeQuotedBlock(node, tag)) {
        flush();
        widgets.add(_quoteCard(context, node));
        continue;
      }

      if (_isBlockTag(tag)) {
        flush();
        widgets.addAll(_blockElement(context, node));
        continue;
      }

      inline.addAll(_inlineNode(context, node, TextStyle(
        fontSize: 15.5,
        height: 1.62,
        color: Theme.of(context).colorScheme.onSurface,
      )));
    }
    flush();
    return widgets;
  }

  List<Widget> _blockElement(BuildContext context, dom.Element element) {
    final tag = element.localName ?? '';
    final classes = element.classes;

    if (tag == 'blockquote') {
      return [_quoteCard(context, element)];
    }

    if (tag == 'pre' || classes.contains('blockcode')) {
      final text = element.text.trim();
      if (text.isEmpty) return const [];
      return [_codeBlock(context, text)];
    }

    if (tag == 'ul' || tag == 'ol') {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, li) in element.querySelectorAll('li').indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tag == 'ol' ? '${index + 1}.' : '•',
                        style: TextStyle(fontSize: 15, height: 1.5, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: SelectableText.rich(
                          TextSpan(children: _inlineNode(context, li, TextStyle(
                            fontSize: 15,
                            height: 1.58,
                            color: Theme.of(context).colorScheme.onSurface,
                          ))),
                          style: const TextStyle(fontSize: 15, height: 1.58),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ];
    }

    if (tag == 'table') {
      return [_tableBlock(context, element)];
    }

    if (tag == 'hr') {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ];
    }

    if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      final spans = _inlineNode(context, element, TextStyle(
        fontSize: 17,
        height: 1.45,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ));
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: SelectableText.rich(TextSpan(children: spans), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.45)),
        ),
      ];
    }

    if (tag == 'iframe' || tag == 'video' || tag == 'audio') {
      final src = element.attributes['src'] ?? element.querySelector('source')?.attributes['src'] ?? '';
      if (src.isEmpty) return const [];
      return [
        Card(
          child: ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('媒体内容'),
            subtitle: Text(src, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => InternalBrowserPage(url: AppConfig.uri(src).toString(), title: '媒体内容'))),
          ),
        ),
      ];
    }

    if (tag == 'div' && classes.contains('comiis_p10')) {
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(children: _inlineNode(context, element, TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ))),
                  style: const TextStyle(fontSize: 13.5, height: 1.55),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    // 普通容器：递归渲染内部块。
    return _blocks(context, element.nodes);
  }

  /// 引用容器：标准的 blockquote，以及皮肤改写后的 div.quote 等。
  bool _isQuoteContainer(String tag, Set<String> classes) {
    if (tag == 'blockquote') return true;
    if (!const {'div', 'section', 'article', 'fieldset'}.contains(tag)) return false;
    return classes.any((name) =>
        name == 'quote' ||
        name == 'blockquote' ||
        name == 'quotecontent' ||
        name == 'comiis_quote' ||
        name.endsWith('_quote'));
  }

  /// 有些皮肤连 quote 类名都不给：叶子里只有一行「某某 发表于 …」再跟正文，
  /// 这类容器同样按引用处理。约束得足够紧，避免把本楼正文吞进卡片。
  bool _looksLikeQuotedBlock(dom.Element element, String tag) {
    if (!const {'div', 'section', 'dl'}.contains(tag)) return false;
    if (element.querySelector('div, p, ul, ol, table, blockquote, fieldset') != null) return false;
    final text = _cleanInline(element.text).trim();
    if (text.isEmpty || text.length > 1500) return false;
    final head = text.length > 48 ? text.substring(0, 48) : text;
    return RegExp(r'^[^。！？]{1,40}?发表于').hasMatch(head);
  }

  /// 引用统一渲染成灰色摘要块：头部是被引用者与时间，正文最多三行，
  /// 点击可展开，避免引用的图片和长文把本楼内容挤到屏幕外。
  Widget _quoteCard(BuildContext context, dom.Element element) {
    final parts = _quoteParts(element);
    if (parts.head.isEmpty && parts.body.isEmpty) {
      // 引用里只有图片等情况，退回普通渲染，至少让图片可见。
      final blocks = _blocks(context, element.nodes);
      if (blocks.isEmpty) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
    }
    return _QuoteCard(head: parts.head, body: parts.body);
  }

  /// 拆出引用头（“某某 发表于 …”）和引用正文。
  ({String head, String body}) _quoteParts(dom.Element element) {
    dom.Element? headNode;
    var head = '';
    for (final link in element.querySelectorAll('a')) {
      final text = _cleanInline(link.text);
      if (text.contains('发表于')) {
        headNode = link;
        head = text;
        break;
      }
    }
    if (headNode == null) {
      for (final font in element.querySelectorAll('font')) {
        final text = _cleanInline(font.text);
        if (text.contains('发表于')) {
          headNode = font;
          head = text;
          break;
        }
      }
    }

    final raw = _quoteText(element, skip: headNode);
    final lines = raw
        .split('\n')
        .map(_cleanInline)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    // 没有链接包裹的引用头就是正文第一行。
    if (head.isEmpty && lines.isNotEmpty && lines.first.contains('发表于')) {
      head = lines.removeAt(0);
    }
    final body = lines.join('\n').trim();
    return (head: head, body: body);
  }

  /// 引用正文的纯文本：保留换行，丢掉图片（引用里的原图会重复占屏）。
  String _quoteText(dom.Element element, {dom.Element? skip}) {
    final buffer = StringBuffer();
    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text);
        return;
      }
      if (node is! dom.Element) return;
      if (identical(node, skip)) {
        buffer.write('\n');
        return;
      }
      final tag = node.localName ?? '';
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      if (tag == 'img' || tag == 'script' || tag == 'style') return;
      for (final child in node.nodes) {
        walk(child);
      }
      if (const {'div', 'p', 'blockquote', 'li', 'tr', 'fieldset', 'table'}.contains(tag)) {
        buffer.write('\n');
      }
    }

    for (final node in element.nodes) {
      walk(node);
    }
    return buffer.toString();
  }

  Widget _codeBlock(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.brightness == Brightness.dark ? const Color(0xFF0B0E13) : const Color(0xFF1D232B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
            child: Row(
              children: [
                const Text('代码', style: TextStyle(color: Colors.white54, fontSize: 11)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('代码已复制')),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(44, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('复制', style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
            child: SelectableText(
              text,
              style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 12.5, height: 1.55, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableBlock(BuildContext context, dom.Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final columnCount = rows.map((row) => row.querySelectorAll('td,th').length).fold(0, (a, b) => a > b ? a : b);
    if (columnCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: scheme.outlineVariant.withValues(alpha: 0.55), width: 0.7),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (final row in rows)
              TableRow(
                children: [
                  for (var i = 0; i < columnCount; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text(
                        _cleanInline(() {
                          final cells = row.querySelectorAll('td,th');
                          return i < cells.length ? cells[i].text : '';
                        }()),
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget? _imageBlock(BuildContext context, dom.Element img) {
    final url = _imageUrl(img);
    if (url.isEmpty) return null;
    final index = widget.images.indexOf(url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          final images = widget.images.isEmpty ? <String>[url] : widget.images;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ImageViewerPage(images: images, initialIndex: index < 0 ? 0 : index),
          ));
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: SmartImage(
            url: url,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            radius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _inlineNode(BuildContext context, dom.Node node, TextStyle style) {
    final spans = <InlineSpan>[];
    if (node is dom.Text) {
      final text = _cleanInline(node.text);
      if (text.isNotEmpty) spans.addAll(_linkifyText(context, text, style));
      return spans;
    }
    if (node is! dom.Element) return spans;

    final tag = node.localName ?? '';
    switch (tag) {
      case 'br':
        spans.add(const TextSpan(text: '\n'));
        return spans;
      case 'b':
      case 'strong':
        return _inlineChildren(context, node, style.copyWith(fontWeight: FontWeight.w700));
      case 'i':
      case 'em':
        return _inlineChildren(context, node, style.copyWith(fontStyle: FontStyle.italic));
      case 'u':
      case 'ins':
        return _inlineChildren(context, node, style.copyWith(decoration: TextDecoration.underline));
      case 's':
      case 'del':
        return _inlineChildren(context, node, style.copyWith(decoration: TextDecoration.lineThrough));
      case 'font':
        final color = _parseColor(node.attributes['color']);
        return _inlineChildren(context, node, color == null ? style : style.copyWith(color: color));
      case 'code':
        return [
          TextSpan(
            text: node.text,
            style: style.copyWith(
              fontFamily: 'monospace',
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ];
      case 'a':
        final href = node.attributes['href'] ?? '';
        if (href.isEmpty || href.startsWith('javascript')) {
          return _inlineChildren(context, node, style);
        }
        final url = AppConfig.uri(href).toString();
        final recognizer = TapGestureRecognizer()..onTap = () => _openLink(context, url);
        _recognizers.add(recognizer);
        return [
          TextSpan(
            text: node.text.isEmpty ? url : node.text,
            style: style.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
            recognizer: recognizer,
          ),
        ];
      case 'img':
        if (_isSmiley(node)) {
          final src = _imageUrl(node);
          if (src.isNotEmpty) {
            return [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Image.network(src, width: 22, height: 22, headers: _headers(), errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ];
          }
          return const [];
        }
        final image = _imageBlock(context, node);
        if (image == null) return const [];
        return [WidgetSpan(alignment: PlaceholderAlignment.middle, child: image)];
      default:
        return _inlineChildren(context, node, style);
    }
  }

  /// 自动识别论坛正文中未被服务端转换为 <a> 的纯文本网址。
  /// 例如隐藏内容里的“https://share.example.com/xxx”也应当可以点击。
  /// 自动识别正文中未被服务端转换为 <a> 标签的纯文本网址。
  List<InlineSpan> _linkifyText(BuildContext context, String text, TextStyle style) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
      }
      var url = match.group(0)!;
      var suffix = '';
      const punctuation = '，。；！？、）》】」』,.;:!?';
      while (url.isNotEmpty && punctuation.contains(url[url.length - 1])) {
        suffix = url[url.length - 1] + suffix;
        url = url.substring(0, url.length - 1);
      }
      if (url.isEmpty) {
        spans.add(TextSpan(text: match.group(0), style: style));
      } else {
        final linkUrl = AppConfig.uri(url).toString();
        final recognizer = TapGestureRecognizer()..onTap = () => _openLink(context, linkUrl);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: url,
          style: style.copyWith(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline),
          recognizer: recognizer,
        ));
        if (suffix.isNotEmpty) spans.add(TextSpan(text: suffix, style: style));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }
    return spans;
  }
  List<InlineSpan> _inlineChildren(BuildContext context, dom.Element element, TextStyle style) {
    final spans = <InlineSpan>[];
    for (final child in element.nodes) {
      spans.addAll(_inlineNode(context, child, style));
    }
    return spans;
  }

  void _openLink(BuildContext context, String url) {
    final thread = RegExp(r'thread-(\d+)-1-1\.html').firstMatch(url);
    if (thread != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThreadPage(tid: int.parse(thread.group(1)!))));
      return;
    }
    final board = RegExp(r'forum-(\d+)-1\.html').firstMatch(url);
    if (board != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BoardThreadsPage(fid: int.parse(board.group(1)!), name: '版块'),
      ));
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && AppConfig.isForumHost(uri.host)) {
      final mod = uri.queryParameters['mod'];
      if (mod == 'post' && uri.queryParameters['action'] == 'reply') {
        widget.onReply?.call();
        return;
      }
      if (mod == 'forumdisplay') {
        final fid = int.tryParse(uri.queryParameters['fid'] ?? '');
        if (fid != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BoardThreadsPage(fid: fid, name: '版块'),
          ));
          return;
        }
      }
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => InternalBrowserPage(url: url)));
  }

  Map<String, String> _headers() {
    final cookie = HttpSession.instance.cookieHeader;
    return {
      'Referer': AppConfig.base,
      'User-Agent': AppConfig.userAgent,
      if (cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  Color? _parseColor(String? value) {
    if (value == null) return null;
    final hex = value.trim().replaceAll('#', '');
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    if (hex.length == 3) {
      final expanded = hex.split('').map((e) => '$e$e').join();
      return Color(int.parse('FF$expanded', radix: 16));
    }
    return switch (value.toLowerCase()) {
      'red' => Colors.red,
      'blue' => Colors.blue,
      'green' => Colors.green,
      'gray' || 'grey' => Colors.grey,
      'orange' => Colors.orange,
      _ => null,
    };
  }

  String _cleanInline(String text) => text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[\uE000-\uF8FF\uFFFD]'), '')
      .replaceAll(RegExp(r'[ \t\r\n]+'), ' ');

  @override
  Widget build(BuildContext context) {
    final cache = _cache ??= _blocks(context, parser.parseFragment(widget.html).nodes);
    if (cache.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Text('该楼层暂无内容', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: cache);
  }
}

/// 楼层里的引用摘要卡片，默认三行，点击展开全文。
class _QuoteCard extends StatefulWidget {
  const _QuoteCard({required this.head, required this.body});

  final String head;
  final String body;

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final collapsed = !_expanded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: widget.body.isEmpty ? null : () => setState(() => _expanded = !_expanded),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.head.isNotEmpty)
                Text(
                  widget.head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (widget.head.isNotEmpty && widget.body.isNotEmpty) const SizedBox(height: 5),
              if (widget.body.isNotEmpty)
                Text(
                  widget.body,
                  maxLines: collapsed ? 3 : null,
                  overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
