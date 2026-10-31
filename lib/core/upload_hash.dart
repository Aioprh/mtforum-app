/// Discuz 手机版发帖页里的附件上传凭证。
///
/// 页面通常写成 `uploadformdata:{uid:"34273", hash:"ab12cd34"}`，但 hash 没有
/// 固定长度——有的版本是 8 位短串，有的是 32 位 md5。早先按 16–40 位匹配，
/// 短 hash 直接被漏掉，上传时就只剩一句「凭证已失效」。
library;

final RegExp _hashPair = RegExp(
  r'''["']?hash["']?\s*:\s*["']([0-9a-zA-Z_-]{6,64})["']''',
  caseSensitive: false,
);

final RegExp _uploadBlock = RegExp(
  r'uploadformdata\s*[:=]\s*\{.{0,300}?\}',
  caseSensitive: false,
  dotAll: true,
);

final RegExp _hashInput = RegExp(
  r'''name=["']hash["'][^>]*?value=["']([0-9a-zA-Z_-]{6,64})["']''',
  caseSensitive: false,
);

final RegExp _hashQuery = RegExp(r'[?&]hash=([0-9a-zA-Z_-]{6,64})', caseSensitive: false);

String findUploadHash(String html) {
  if (html.isEmpty) return '';
  // 先认 uploadformdata 声明里的那个，避免误抓页面里其它叫 hash 的变量。
  final block = _uploadBlock.firstMatch(html);
  if (block != null) {
    final inside = _hashPair.firstMatch(block.group(0)!);
    if (inside != null) return inside.group(1)!;
  }
  final direct = _hashPair.firstMatch(html);
  if (direct != null) return direct.group(1)!;
  final input = _hashInput.firstMatch(html);
  if (input != null) return input.group(1)!;
  return _hashQuery.firstMatch(html)?.group(1) ?? '';
}
