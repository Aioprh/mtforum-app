/// 正文 BBCode 里的图片 / 附件引用。
///
/// 编辑页给的是一段纯文本原稿，图片只看得到 `[attachimg]123[/attachimg]`
/// 这样的标签。把标签解析出来，编辑时可以单独铺一条缩略图，保存时也要按
/// 这些 aid 把附件绑回帖子。
library;

/// 一张图片或一个附件在正文中的位置。
class BbcodeMediaRef {
  const BbcodeMediaRef({
    required this.tag,
    required this.url,
    required this.aid,
    required this.image,
  });

  /// 正文里的原始标记，删除时按它精确移除。
  final String tag;

  /// 原始地址。附件是站内相对路径，外链图原样保留，交给 AppConfig.uri 归一。
  final String url;

  /// 附件 id；`[img]` 这类外链图为 0。
  final int aid;

  /// `[attach]` 是普通附件，没有可预览的图。
  final bool image;
}

/// 附件在站内的访问地址。
String attachmentMediaUrl(int aid) => 'forum.php?mod=attachment&aid=$aid&noupdate=yes';

final RegExp _attachImage = RegExp(
  r'\[attachimg\]\s*(\d+)\s*\[/attachimg\]',
  caseSensitive: false,
);
final RegExp _attachFile = RegExp(
  r'\[attach\]\s*(\d+)\s*\[/attach\]',
  caseSensitive: false,
);

/// `[img]https://…[/img]` 与 `[img=600,400]https://…[/img]`。
final RegExp _externalImage = RegExp(
  r'\[img(?:=[^\]]*)?\]([^\[]+)\[/img\]',
  caseSensitive: false,
);

/// 按出现顺序解析正文里的图片与附件，同一标记只保留一次。
List<BbcodeMediaRef> parseBbcodeMedia(String text) {
  if (text.isEmpty) return const <BbcodeMediaRef>[];

  // 三类标记分别扫，最后按在正文里的位置排回去。分类扫再依次输出会把
  // 「图片 → 附件 → 图片」的原始顺序打乱，编辑页缩略图跟着乱跳。
  final found = <({int start, String tag, String url, int aid, bool image})>[];

  for (final match in _attachImage.allMatches(text)) {
    final aid = int.tryParse(match.group(1) ?? '') ?? 0;
    if (aid <= 0) continue;
    found.add((
      start: match.start,
      tag: match.group(0)!,
      url: attachmentMediaUrl(aid),
      aid: aid,
      image: true,
    ));
  }
  for (final match in _attachFile.allMatches(text)) {
    final aid = int.tryParse(match.group(1) ?? '') ?? 0;
    if (aid <= 0) continue;
    found.add((
      start: match.start,
      tag: match.group(0)!,
      url: attachmentMediaUrl(aid),
      aid: aid,
      image: false,
    ));
  }
  for (final match in _externalImage.allMatches(text)) {
    final url = (match.group(1) ?? '').trim();
    if (url.isEmpty) continue;
    found.add((
      start: match.start,
      tag: match.group(0)!,
      url: url,
      aid: 0,
      image: true,
    ));
  }

  found.sort((a, b) => a.start.compareTo(b.start));

  final result = <BbcodeMediaRef>[];
  final seen = <String>{};
  for (final item in found) {
    if (!seen.add(item.tag)) continue;
    result.add(BbcodeMediaRef(
      tag: item.tag,
      url: item.url,
      aid: item.aid,
      image: item.image,
    ));
  }
  return result;
}

/// 正文引用到的附件 aid，提交表单时用来把附件绑到本帖。
List<int> attachmentIdsIn(String message) {
  final ids = <int>[];
  for (final item in parseBbcodeMedia(message)) {
    if (item.aid > 0 && !ids.contains(item.aid)) ids.add(item.aid);
  }
  return ids;
}
