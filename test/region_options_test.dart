import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/data/forum_repository.dart';

/// 地区 ajax 的返回解析。
///
/// 站点把一段 `<select>` 塞进 CDATA 里返回，option 的 `did` 才是下一级要用的
/// 主键，文本只是给人看的。占位项（`-省份-`）value 为空、没有 did，必须丢掉，
/// 否则选择器第一行会多出个点不动的「-省份-」。
void main() {
  const provinceXml =
      '<?xml version="1.0" encoding="utf-8"?><root><![CDATA['
      '<select name="resideprovince" id="resideprovince">'
      '<option value="">-省份-</option>'
      '<option did="2" value="天津市" selected="selected">天津市</option>'
      '<option did="19" value="广东省">广东省</option>'
      '<option did="34" value="澳门特别行政区">澳门特别行政区</option>'
      '</select>'
      '<select name="residecity" id="residecity">'
      '<option value="">-城市-</option>'
      '<option did="63" value="大港区">大港区</option>'
      '</select>'
      ']]></root>';

  test('从 CDATA 里取出指定层级并过滤占位项', () {
    final items = ForumRepository.parseRegionOptions(provinceXml, 'resideprovince');
    expect(items.map((e) => e.name).toList(), ['天津市', '广东省', '澳门特别行政区']);
    expect(items.map((e) => e.id).toList(), [2, 19, 34]);
  });

  test('选错层级时能取到对应的那一张下拉', () {
    final items = ForumRepository.parseRegionOptions(provinceXml, 'residecity');
    expect(items.length, 1);
    expect(items.first.name, '大港区');
    expect(items.first.id, 63);
  });

  test('返回里没有这一级就返回空列表', () {
    expect(ForumRepository.parseRegionOptions(provinceXml, 'residedist'), isEmpty);
  });

  test('没有 CDATA 外壳也能解析', () {
    const plain = '<select name="residecity">'
        '<option value="">-城市-</option>'
        '<option did="289" value="广州市">广州市</option>'
        '</select>';
    final items = ForumRepository.parseRegionOptions(plain, 'residecity');
    expect(items.single.name, '广州市');
    expect(items.single.id, 289);
  });

  test('空响应与服务端报错都不炸', () {
    expect(ForumRepository.parseRegionOptions('', 'resideprovince'), isEmpty);
    expect(
      ForumRepository.parseRegionOptions(
        '<?xml version="1.0"?><root><![CDATA[抱歉，没有找到相应的地区]]></root>',
        'resideprovince',
      ),
      isEmpty,
    );
  });

  test('缺 did 的选项跳过，避免拿 0 去查下一级', () {
    const xml = '<select name="residecity">'
        '<option value="某地">某地</option>'
        '<option did="7" value="某市">某市</option>'
        '</select>';
    final items = ForumRepository.parseRegionOptions(xml, 'residecity');
    expect(items.single.name, '某市');
  });
}
