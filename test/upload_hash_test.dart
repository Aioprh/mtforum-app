import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/core/upload_hash.dart';

/// 发帖页的上传凭证解析。站点把 hash 写成 8 位短串，早期按 16 位起步匹配，
/// 结果永远取不到，用户只看到「上传凭证已失效」。
void main() {
  test('8 位短 hash 也要认得（uploadformdata 声明）', () {
    const html = '<script>var uploadformdata = {uid:"34273", hash:"8a7b6c5d"};</script>';
    expect(findUploadHash(html), '8a7b6c5d');
  });

  test('32 位 md5 正常解析', () {
    const html = """uploadformdata:{uid:"1",hash:"e10adc3949ba59abbe56e057f20f883e"}""";
    expect(findUploadHash(html), 'e10adc3949ba59abbe56e057f20f883e');
  });

  test('优先取 uploadformdata 里的，不被页面其它 hash 干扰', () {
    const html = '''
      <script>
        var passwordHash = "ffffffffffffffffffffffffffffffff";
        var uploadformdata = {'uid':'1', 'hash':'abc12345'};
      </script>
    ''';
    expect(findUploadHash(html), 'abc12345');
  });

  test('隐藏域与查询串里的 hash 作为兜底', () {
    expect(findUploadHash('<input type="hidden" name="hash" value="deadbeef" />'), 'deadbeef');
    expect(findUploadHash('<a href="misc.php?mod=swfupload&hash=cafe1234">上传</a>'), 'cafe1234');
  });

  test('页面里确实没有凭证时返回空串', () {
    expect(findUploadHash('<div>普通页面</div>'), '');
    expect(findUploadHash(''), '');
  });
}
