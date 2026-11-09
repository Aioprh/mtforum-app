import 'package:html/dom.dart' as dom;

/// 认出帖子里的代码块，并把源码原样取出来。
///
/// Discuz 的代码块没有标准结构，各套模板写法都不一样：
///
/// ```
/// <div class="comiis_blockcode"><div class="bg_f b_l"><ol><li>第一行<br/></li>…
/// <div class="blockcode"><blockquote>code…</blockquote></div>
/// <pre><code>code…</code></pre>
/// ```
///
/// 手机模板用的是第一种：每一行代码是一个 `<li>`，行号靠 `<ol>` 自动生成。
/// 直接读 `element.text` 会把所有行粘成一行——`li` 之间没有换行符——所以
/// 必须按 `li` 拆行，否则代码块里只剩一坨读不懂的长串。
class CodeBlock {
  const CodeBlock._();

  /// class 里带这几个词的就是代码块。
  ///
  /// 只认 `blockcode` 结尾的名字：`comiis_blockcode`、`blockcode`、
  /// `codeblock` 都能命中，普通正文里极少出现这类 class，不会误判。
  static const Set<String> _classNames = {'blockcode', 'codeblock'};

  static bool isCodeBlock(String tag, Iterable<String> classes) {
    if (tag == 'pre') return true;
    for (final raw in classes) {
      final name = raw.toLowerCase();
      if (_classNames.contains(name)) return true;
      if (name.endsWith('_blockcode') || name.endsWith('-blockcode')) return true;
    }
    return false;
  }

  /// 取出代码原文，行与行之间是 `\n`，缩进保留。
  static String extract(dom.Element element) {
    final items = element.querySelectorAll('li');
    // 有 `<li>` 就说明是按行排的代码；普通段落不会走到这里（代码块分支
    // 优先），所以此时把每个 li 当作一行。
    final raw = items.isEmpty
        ? _text(element)
        : items.map((li) => _trimNewlines(_text(li))).join('\n');
    return _tidy(raw);
  }

  /// 深度优先拼接文本：`<br>` 换行，块级元素边界换行，其余原样接上。
  static String _text(dom.Node node) {
    final parts = <String>[];
    var atLineStart = true;

    void write(String text) {
      if (text.isEmpty) return;
      parts.add(text);
      atLineStart = text.endsWith('\n');
    }

    void walk(dom.Node current) {
      if (current is dom.Text) {
        var text = current.text.replaceAll('\u00A0', ' ');
        // `<br/>` 之后跟着的源码换行只是 HTML 的排版换行，再写一次就变成
        // 「每行代码之间空一行」——手机上等于把代码块撑成两倍高。行首只
        // 去掉换行符，空格是缩进，得留着。
        if (atLineStart) {
          text = text.replaceFirst(RegExp(r'^[\r\n]+'), '');
          if (text.isEmpty) return;
        }
        write(text);
        return;
      }
      if (current is! dom.Element) return;
      final tag = current.localName ?? '';
      if (tag == 'script' || tag == 'style') return;
      if (tag == 'br') {
        write('\n');
        return;
      }
      final block = const {
        'div', 'p', 'li', 'tr', 'ol', 'ul', 'table', 'blockquote', 'pre',
      }.contains(tag);
      if (block && !atLineStart) write('\n');
      for (final child in current.nodes) {
        walk(child);
      }
      if (block && !atLineStart) write('\n');
    }

    walk(node);
    return parts.join();
  }

  static String _trimNewlines(String text) =>
      text.replaceFirst(RegExp(r'^[\n]+'), '').replaceFirst(RegExp(r'[\n]+$'), '');

  /// 统一换行符、去掉行尾空白和首尾空行，内部空行保留（代码里它们是结构）。
  static String _tidy(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
        .toList();
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }
}
