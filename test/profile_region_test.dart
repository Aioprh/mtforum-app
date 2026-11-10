import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 居住地解析。
///
/// `#residedistrictbox` 在「填过地址」和「没填地址」两种状态下结构完全不同，
/// 早先只读容器文本，没填地址时会把整张省份下拉拼成一句
/// 「省份-北京市天津市河北省…」直接怼进输入框——用户截图里的那个 bug。
void main() {
  String page(String box) => '''
<form action="home.php?mod=spacecp&ac=profile&op=base" method="post">
  <input type="hidden" name="formhash" value="617d2811" />
  <input type="text" name="occupation" value="" />
  <input type="text" name="realname" value="百晓生" />
  <input type="hidden" name="birthyear" value="2001" />
  <input type="hidden" name="birthmonth" value="12" />
  <input type="hidden" name="birthday" value="21" />
  <select name="gender"><option value="0">保密</option><option value="2" selected="selected">女</option></select>
  <div class="flex comiis_vrzstyle">$box</div>
</form>
''';

  String textBox(String text) =>
      '<div id="residedistrictbox"><div class="comiis_styli">$text&nbsp;'
      '<a href="javascript:;" class="f_g">[修改]</a></div></div>';

  String selectBox({String province = '', String city = '', String dist = ''}) {
    String options(List<String> names, String selected) {
      final buffer = StringBuffer('<option value="">-占位-</option>');
      for (final name in names) {
        final mark = name == selected ? ' selected="selected"' : '';
        buffer.write('<option did="1" value="$name"$mark>$name</option>');
      }
      return buffer.toString();
    }

    return '<div id="residedistrictbox">'
        '<select name="resideprovince">'
        '${options(['北京市', '天津市', '河北省', '广东省'], province)}'
        '</select>'
        '<select name="residecity">'
        '${options(['大港区', '和平区', '广州市'], city)}'
        '</select>'
        '<select name="residedist">'
        '${options(['中塘镇', '古林街道'], dist)}'
        '</select>'
        '</div>';
  }

  test('已填地址时读的是那一行文本', () {
    final data = ForumRepository.parseProfileBaseHtml(page(textBox('天津市 大港区')));
    expect(data.resideText, '天津市 大港区');
    // 纯文本形态拿不到层级字段，交给保存时的兜底拆分。
    expect(data.hasRegion, isFalse);
    expect(data.occupation, '');
    expect(data.realname, '百晓生');
    expect(data.gender, 2);
  });

  test('没填地址时容器里是整张省下拉，不能把选项全拼成地址', () {
    final data = ForumRepository.parseProfileBaseHtml(page(selectBox()));
    expect(data.resideText, isEmpty);
    expect(data.hasRegion, isFalse);
  });

  test('下拉里选中了省市区就按字段还原', () {
    final data = ForumRepository.parseProfileBaseHtml(
      page(selectBox(province: '天津市', city: '大港区', dist: '中塘镇')),
    );
    expect(data.resideProvince, '天津市');
    expect(data.resideCity, '大港区');
    expect(data.resideDist, '中塘镇');
    expect(data.resideText, '天津市 大港区 中塘镇');
    expect(data.hasRegion, isTrue);
  });

  test('只选中省份也能显示', () {
    final data = ForumRepository.parseProfileBaseHtml(page(selectBox(province: '广东省')));
    expect(data.resideProvince, '广东省');
    expect(data.resideText, '广东省');
  });

  test('隐藏域形态同样认得', () {
    final box = '<div id="residedistrictbox">'
        '<input type="hidden" name="resideprovince" value="广东省" />'
        '<input type="hidden" name="residecity" value="广州市" />'
        '<input type="hidden" name="residedist" value="天河区" />'
        '</div>';
    final data = ForumRepository.parseProfileBaseHtml(page(box));
    expect(data.resideText, '广东省 广州市 天河区');
  });

  test('没有 select 的一长串省份文本仍按脏数据丢弃', () {
    final dump = textBox(
      '省份-北京市天津市河北省山西省内蒙古自治区辽宁省吉林省黑龙江省'
      '上海市江苏省浙江省安徽省福建省江西省山东省河南省',
    );
    final data = ForumRepository.parseProfileBaseHtml(page(dump));
    expect(data.resideText, isEmpty);
  });

  test('普通地址不会被省份计数误伤', () {
    final data = ForumRepository.parseProfileBaseHtml(page(textBox('广东省 广州市 天河区')));
    expect(data.resideText, '广东省 广州市 天河区');
  });

  test('没有 residedistrictbox 时返回空地址', () {
    final data = ForumRepository.parseProfileBaseHtml(page(''));
    expect(data.resideText, isEmpty);
    expect(data.hasRegion, isFalse);
  });

  test('拆分兜底：直辖市文本拆成省 + 区', () {
    expect(ForumRepository.splitRegion('天津市 大港区'), ('天津市', '', '大港区', ''));
    expect(
      ForumRepository.splitRegion('广东省 广州市 天河区 石牌街道'),
      ('广东省', '广州市', '天河区', '石牌街道'),
    );
    expect(ForumRepository.splitRegion(''), ('', '', '', ''));
  });
}
