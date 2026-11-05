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

    test('只取正文所在那张表单，页头搜索框与上传表单的字段一概不碰', () {
      // 真实编辑页的结构：页头一个搜索表单、侧边一个上传表单，
      // 编辑表单在中间。整页抓字段会把 `mod=forum`、`srchtxt` 一起交回去。
      final doc = parser.parse('''
        <form id="searchform" action="search.php">
          <input type="hidden" name="mod" value="forum">
          <input type="text" name="srchtxt" value="请输入搜索内容">
        </form>
        <form id="postform" method="post">
          <input type="hidden" name="fid" value="42">
          <input type="hidden" name="tid" value="176076">
          <input type="hidden" name="pid" value="12089521">
          <input type="hidden" name="page" value="">
          <input type="hidden" name="delattachop" value="0">
          <input type="checkbox" name="usesig" value="1" checked>
          <select name="mygroupid"><option value="" selected>不指定</option></select>
          <textarea name="message">正文</textarea>
        </form>
        <form id="uploadform">
          <input type="hidden" name="uid" value="34273">
          <input type="hidden" name="hash" value="a663a276">
          <input type="hidden" name="localid[]" value="">
        </form>
      ''');
      final fields = ForumRepository.editFormFields(doc);

      expect(fields['fid'], '42');
      expect(fields['pid'], '12089521');
      expect(fields['usesig'], '1');
      // 页头 / 上传表单的字段一旦混进去，服务端会 200 把表单原样退回来。
      expect(fields.containsKey('mod'), isFalse);
      expect(fields.containsKey('srchtxt'), isFalse);
      expect(fields.containsKey('uid'), isFalse);
      expect(fields.containsKey('hash'), isFalse);
      expect(fields.containsKey('localid[]'), isFalse);
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

  group('editAttachments', () {
    test('图片与文件附件都能读出来，正文没引用的也算', () {
      // 克米模板真实结构：图片在 imageattach / image_ 标记里，文件在
      // attachname 标记里，title 里带文件名和大小。
      final doc = parser.parse('''
        <table class="imgl"><tr>
          <td id="image_td_382627">
            <a href="javascript:;" title="scaled_187137.jpg" id="imageattach382627">
              <img src="https://oos.binmt.cc/image/000/38/26/27_300_300.jpg" id="image_382627">
            </a>
            <input type="hidden" name="attachupdate[382627]">
          </td>
        </tr></table>
        <table><tbody id="attach_382585">
          <tr><td>
            <p id="attach382585">
              <a href="javascript:;" id="attachname382585" isimage="1"
                 title="Screenshot_2026-11-06-00-47-26.jpg
上传日期: 2026-11-6 00:49
文件大小: 183.79 KB">Screenshot_2026-11-06-00- ...</a>
            </p>
            <div id="attach_preview_382585_menu"><img src="https://oos.binmt.cc/image/000/38/25/85_300_300.jpg" id="image_382585"></div>
            <input type="text" name="attachnew[382585][description]">
          </td></tr>
        </tbody></table>
      ''');
      final list = ForumRepository.editAttachments(doc);
      expect(list.map((e) => e.aid), [382627, 382585]);

      final image = list.first;
      expect(image.isImage, isTrue);
      expect(image.name, 'scaled_187137.jpg');
      expect(image.thumbUrl, isNotEmpty);

      final file = list.last;
      expect(file.isImage, isTrue);
      expect(file.name, 'Screenshot_2026-11-06-00-47-26.jpg');
      expect(file.sizeText, '183.79 KB');
      expect(file.thumbUrl, isNotEmpty);
    });

    test('普通文件附件用文件名，不当成图片', () {
      final doc = parser.parse('''
        <tbody id="attach_99"><tr><td>
          <a id="attachname99" title="MT管理器_v2.5.5.apk
上传日期: 2026-11-1 10:00
文件大小: 8.21 MB">MT管理器_v2.5.5.apk</a>
        </td></tr></tbody>
      ''');
      final list = ForumRepository.editAttachments(doc);
      expect(list, hasLength(1));
      expect(list.single.isImage, isFalse);
      expect(list.single.name, 'MT管理器_v2.5.5.apk');
      expect(list.single.sizeText, '8.21 MB');
      expect(list.single.thumbUrl, isEmpty);
    });

    test('没有任何附件时返回空列表', () {
      expect(ForumRepository.editAttachments(parser.parse('<form></form>')), isEmpty);
    });

    test('只有带 delAttach / delImgAttach 的附件才允许删除', () {
      // 网页版编辑页行尾的「删除」就是 delAttach(aid,0)（普通附件）和
      // delImgAttach(aid,0)（图片）；服务端不给这个链接，说明没权限删。
      final doc = parser.parse('''
        <table><tr><td>
          <a id="imageattach11" title="a.jpg"><img src="https://x/a.jpg" id="image_11"></a>
          <a href="javascript:;" onclick="delImgAttach(11,0);return false;">删除</a>
        </td></tr></table>
        <table><tbody id="attach_22"><tr><td>
          <a id="attachname22" title="b.apk">b.apk</a>
          <a href="javascript:;" onclick="delAttach(22,0);return false;">删除</a>
        </td></tr></tbody></table>
        <table><tbody id="attach_33"><tr><td>
          <a id="attachname33" title="c.apk">c.apk</a>
        </td></tr></tbody></table>
      ''');
      final list = ForumRepository.editAttachments(doc);
      expect(list.map((e) => e.aid), [11, 22, 33]);
      expect(list.map((e) => e.deletable), [true, true, false]);
    });
  });
}