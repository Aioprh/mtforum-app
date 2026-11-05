import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as parser;
import 'package:mt_forum/data/forum_repository.dart';

void main() {
  group('editFormFields', () {
    test('带回分类、标签、售价、投票与已有附件描述', () {
      final doc = parser.parse('''
        <form method="post">
          <input type="hidden" name="formhash" value="deadbeef">
          <input type="hidden" name="posttime" value="123">
          <input type="hidden" name="typeid" value="12">
          <input type="text" name="tags" value="教程,破解">
          <input type="hidden" name="attachnew[99][description]" value="旧图">
          <input type="hidden" name="delete" value="1">
          <textarea name="polloptions">选项一\n选项二</textarea>
          <input type="checkbox" name="usesig" value="1" checked>
          <input type="checkbox" name="anonymous" value="1">
          <select name="price">
            <option value="0">免费</option>
            <option value="5" selected>5 金币</option>
          </select>
          <input type="submit" name="editsubmit" value="保存">
          <button type="submit" name="delete" value="1">删除</button>
          <textarea name="message">正文</textarea>
          <input type="text" name="subject" value="标题">
        </form>
      ''');
      final fields = ForumRepository.editFormFields(doc);

      expect(fields['typeid'], '12');
      expect(fields['tags'], '教程,破解');
      expect(fields['attachnew[99][description]'], '旧图');
      expect(fields['polloptions'], '选项一\n选项二');
      expect(fields['usesig'], '1');
      expect(fields['price'], '5');
      // 未勾选的 checkbox 浏览器不会提交。
      expect(fields.containsKey('anonymous'), isFalse);
      // 正文、标题、凭证由调用方自己填，不能被旧值覆盖。
      expect(fields.containsKey('formhash'), isFalse);
      expect(fields.containsKey('posttime'), isFalse);
      expect(fields.containsKey('message'), isFalse);
      expect(fields.containsKey('subject'), isFalse);
      expect(fields.containsKey('editsubmit'), isFalse);
      // 编辑页上的 delete 绝不能带回，否则保存会变成删帖。
      expect(fields.containsKey('delete'), isFalse);
    });

    test('关闭的签名开关留空值，和「没有这个开关」区分开', () {
      final doc = parser.parse('''
        <form>
          <input type="checkbox" name="usesig" value="1">
          <input type="hidden" name="fid" value="2">
        </form>
      ''');
      final fields = ForumRepository.editFormFields(doc);
      expect(fields.containsKey('usesig'), isTrue);
      expect(fields['usesig'], '');
      expect(fields['fid'], '2');
    });

    test('下拉框取选中项，没有 selected 时取第一项', () {
      final doc = parser.parse('''
        <form>
          <select name="typeid"><option value="3">求助</option><option value="4" selected>教程</option></select>
          <select name="sortid"><option value="7">默认</option></select>
        </form>
      ''');
      final fields = ForumRepository.editFormFields(doc);
      expect(fields['typeid'], '4');
      expect(fields['sortid'], '7');
    });

    test('没有表单字段时返回空 map', () {
      expect(ForumRepository.editFormFields(parser.parse('<div>无表单</div>')), isEmpty);
    });
  });

  group('attachmentIdsIn', () {
    test('按正文引用顺序返回附件 id', () {
      expect(
        ForumRepository.attachmentIdsIn('a[attachimg]9[/attachimg]b[attach]3[/attach]c'),
        [9, 3],
      );
    });
  });
}
