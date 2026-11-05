/// 解析 Discuz `misc.php?mod=swfupload&operation=upload` 的返回。
///
/// 服务端有两种输出（看 `forum_upload` 类走的哪个分支）：
///
/// ```
/// DISCUZUPLOAD|1|0|1234|1|202401/01/abc.jpg|photo.jpg|0     // 带 type，8 段
/// DISCUZUPLOAD|0|1234|1|0                                    // 不带 type，5 段
/// ```
///
/// 两个格式的字段位置不一样，按段数分开解，不能用一个正则硬套。
/// 另外 hash 校验不过时服务端是 `exit()`，响应体为空——那种情况返回 null，
/// 由调用方给出「凭证被拒绝」这类可读提示。
library;

class UploadResult {
  const UploadResult({
    required this.errorCode,
    required this.aid,
    this.attachment = '',
    this.filename = '',
  });

  /// 0 表示成功，其余是 Discuz 的错误码（1–11，见提示文案表）。
  final int errorCode;
  final int aid;
  final String attachment;
  final String filename;

  bool get ok => errorCode == 0 && aid > 0;

  @override
  String toString() => 'UploadResult(error=$errorCode, aid=$aid, file=$filename)';
}

UploadResult? parseUploadResult(String body) {
  final start = body.indexOf('DISCUZUPLOAD');
  if (start < 0) return null;

  final parts = _clean(body.substring(start)).split('|');
  // parts[0] 是 DISCUZUPLOAD 本身，后面才是字段。
  if (parts.length >= 8) {
    // 8 段里 aid 的位置随模板/插件版本漂移，实测两种：
    //
    //   DISCUZUPLOAD|type|error|aid|isimage|attachment|filename|sizelimit
    //   DISCUZUPLOAD|type|aid|pid|cid|attachment|filename|remote
    //
    // 拿 `|type|error|aid|` 硬套第二种会把 error 当成错误码：真实返回
    // `DISCUZUPLOAD|1|9|0|1|202611/06/xxx.png|p.png|0`（aid=9、还没绑帖子），
    // 按旧写法读成「错误码 9、aid 0」，图明明传上去了却报上传失败。
    //
    // 第六段是落盘相对路径，成功才非空，先用它判成败，再取两段里非零的那个当 aid。
    final attachment = parts[5];
    if (attachment.isEmpty) {
      return UploadResult(
        errorCode: int.tryParse(parts[2]) ?? -1,
        aid: 0,
        filename: parts[6],
      );
    }
    final byError = int.tryParse(parts[2]) ?? 0;
    final byPid = int.tryParse(parts[3]) ?? 0;
    return UploadResult(
      errorCode: 0,
      aid: byError > 0 ? byError : byPid,
      attachment: attachment,
      filename: parts[6],
    );
  }
  if (parts.length >= 5) {
    // 不带 type：|error|aid|isimage|sizelimit
    return UploadResult(
      errorCode: int.tryParse(parts[1]) ?? -1,
      aid: int.tryParse(parts[2]) ?? 0,
    );
  }
  return null;
}

/// 截掉尾部可能跟着的 HTML / 脚本，避免最后一段被污染。
String _clean(String raw) {
  final cut = raw.indexOf('<');
  return cut >= 0 ? raw.substring(0, cut) : raw;
}
