import 'dart:convert';

import '../data/smilies.dart';

/// 把用户输入的 BBCode 还原成站点会下发的 HTML。
///
/// 私信编辑器用的是官网那套 BBCode：表情是 `[呵呵]`，加粗是 `[b]`，链接是
/// `[url=…]`。服务端收到后会转成 `<img src="…/smiley/…">`、`<b>` 再存下来；
/// 本机刚发出的那条还没经过服务端，只能自己转一遍，气泡里才和对方看到的一致。
///
/// 只处理私信允许的几种标记：加粗、斜体、下划线、颜色、链接、引用、代码、
/// 官方表情。`[img]` 在私信里被站点关闭（`allowimgcode = 0`），不在这里支持。
String bbcodeToHtml(String source) {
  if (source.trim().isEmpty) return '';

  // 先整体转义：私信正文里出现的 `<` 只应该当文字看。
  var text = const HtmlEscape(HtmlEscapeMode.element).convert(source);

  // 代码块里的 BBCode 原样保留，先挖出来占位，最后再放回去。
  final codeBlocks = <String>[];
  text = text.replaceAllMapped(_codePattern, (match) {
    final code = (match.group(1) ?? '').trim();
    codeBlocks.add('<pre>$code</pre>');
    return '\u0000CODE${codeBlocks.length - 1}\u0000';
  });

  text = text.replaceAllMapped(
    _quotePattern,
    (match) => '<blockquote>${match.group(1) ?? ''}</blockquote>',
  );

  // [url=地址]文字[/url]
  text = text.replaceAllMapped(_namedLinkPattern, (match) {
    final href = match.group(1) ?? '';
    final label = (match.group(2) ?? '').trim();
    return '<a href="$href">${label.isEmpty ? href : label}</a>';
  });
  // [url]地址[/url]
  text = text.replaceAllMapped(
    _bareLinkPattern,
    (match) => '<a href="${match.group(1) ?? ''}">${match.group(1) ?? ''}</a>',
  );

  text = _wrap(text, 'b', 'b');
  text = _wrap(text, 'i', 'i');
  text = _wrap(text, 'u', 'u');

  text = text.replaceAllMapped(_colorPattern, (match) {
    final color = (match.group(1) ?? '').trim();
    if (color.isEmpty) return match.group(2) ?? '';
    return '<font color="$color">${match.group(2) ?? ''}</font>';
  });

  // 表情放在最后：它的代码本身就是 `[呵呵]`，不会和上面的标签冲突。
  for (final entry in kSmileyUrlByCode.entries) {
    if (!text.contains(entry.key)) continue;
    text = text.replaceAll(entry.key, '<img src="${entry.value}">');
  }

  text = text.replaceAll('\r\n', '\n').replaceAll('\n', '<br>');

  for (var i = 0; i < codeBlocks.length; i++) {
    text = text.replaceAll('\u0000CODE$i\u0000', codeBlocks[i]);
  }
  return text;
}

final RegExp _codePattern = RegExp(r'\[code\]([\s\S]*?)\[/code\]', caseSensitive: false);
final RegExp _quotePattern = RegExp(r'\[quote\]([\s\S]*?)\[/quote\]', caseSensitive: false);
final RegExp _namedLinkPattern =
    RegExp(r'\[url=([^\]]+)\]([\s\S]*?)\[/url\]', caseSensitive: false);
final RegExp _bareLinkPattern = RegExp(r'\[url\]([\s\S]*?)\[/url\]', caseSensitive: false);
final RegExp _colorPattern =
    RegExp(r'\[color=([#a-zA-Z0-9(),.%\s-]+)\]([\s\S]*?)\[/color\]', caseSensitive: false);

String _wrap(String text, String tag, String htmlTag) {
  final pattern = RegExp('\\[$tag\\]([\\s\\S]*?)\\[/$tag\\]', caseSensitive: false);
  return text.replaceAllMapped(
    pattern,
    (match) => '<$htmlTag>${match.group(1) ?? ''}</$htmlTag>',
  );
}
